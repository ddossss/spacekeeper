namespace Spacekeeper.Core;

public sealed class Cleaner(Store store, IRecycler recycler, Func<List<CacheRule>>? cacheRules = null, Func<CacheRule, bool>? running = null)
{
    public HistoryRecord Clean(CleanupRequest request, CancellationToken token, bool scheduled = false)
    {
        using var operationLock = store.Acquire(); var settings = store.LoadSettings();
        if (scheduled && (!settings.ScheduleEnabled || request.Kind != CleanupKind.Cache)) throw new KeeperException("정기 캐시 청소가 꺼져 있습니다.");
        var entries = request.Files.DistinctBy(f => f.Path, Safety.Comparer).ToList();
        if (entries.Count == 0) throw new KeeperException("정리할 파일을 선택해 주세요.");
        var selected = entries.Select(f => f.Path).ToHashSet(Safety.Comparer);
        var keepers = new Dictionary<string, FileEntry>(Safety.Comparer);
        if (request.Kind == CleanupKind.Duplicates)
        {
            var groups = request.Groups ?? throw new KeeperException("검사 결과에 없는 파일이 선택되었습니다.");
            if (!selected.IsSubsetOf(groups.SelectMany(g => g.Files).Select(f => f.Path))) throw new KeeperException("검사 결과에 없는 파일이 선택되었습니다.");
            foreach (var group in groups.Where(g => g.Files.Any(f => selected.Contains(f.Path))))
            {
                var keeper = group.Files.FirstOrDefault(f => !selected.Contains(f.Path)) ?? throw new KeeperException("각 중복 그룹에서 최소 한 파일은 남겨야 합니다.");
                Safety.Root(keeper.Root);
                if (keeper.Hash == null || Safety.Hash(keeper, token) != keeper.Hash) throw new KeeperException("검사 후 파일이 변경되었습니다. 다시 검사해 주세요: {0}", keeper.Path);
                foreach (var entry in entries.Where(e => group.Files.Any(f => Safety.Same(f.Path, e.Path))))
                {
                    if (entry.Hash != keeper.Hash) throw new KeeperException("파일 내용이 서로 다릅니다.");
                    keepers[entry.Path] = keeper;
                }
            }
        }
        var record = new HistoryRecord { Kind = scheduled ? "정기 캐시 청소" : request.Kind switch { CleanupKind.Cache => "캐시 정리", CleanupKind.Duplicates => "중복 파일 정리", _ => "대용량 파일 정리" } };
        store.SaveHeader(record); long moved = 0;
        var rules = request.Kind == CleanupKind.Cache ? (cacheRules?.Invoke() ?? CacheRules.Discover()) : [];
        foreach (var entry in entries)
        {
            if (token.IsCancellationRequested) { record.Note = new("남은 작업을 취소했습니다."); break; }
            if (scheduled && moved + entry.Bytes > settings.MaximumBytes) { record.Note = new("1회 정리 한도에 도달해 나머지 파일은 보관했습니다."); continue; }
            var item = new HistoryItem { Source = entry.Path, Bytes = entry.Bytes };
            try
            {
                if (Safety.Excluded(entry.Path, settings.Exclusions)) throw new KeeperException("검사 제외 목록에 있는 파일입니다.");
                Safety.Validate(entry);
                if (request.Kind == CleanupKind.Cache)
                {
                    var rule = rules.FirstOrDefault(r => Safety.Same(r.Root, entry.Root) && Safety.Contains(r.Root, entry.Path));
                    if (request.MinimumDays < 7 || rule == null || (running?.Invoke(rule) ?? rule.Running) || !settings.CacheIDs.Contains(rule.ID))
                        throw new KeeperException("지원하지 않는 캐시이거나 앱이 실행 중입니다: {0}", entry.Name);
                    var days = scheduled ? Math.Max(settings.MinimumDays, request.MinimumDays) : request.MinimumDays;
                    if (FileStamp.Read(entry.Path).LastUsedUtc >= DateTime.UtcNow.AddDays(-days)) throw new KeeperException("최근 사용한 캐시는 보관합니다: {0}", entry.Name);
                }
                else Safety.Root(entry.Root);
                if (request.Kind == CleanupKind.Duplicates && (Safety.Hash(entry, token) != entry.Hash || Safety.Hash(keepers[entry.Path], token) != entry.Hash))
                    throw new KeeperException("검사 후 파일이 변경되었습니다. 다시 검사해 주세요: {0}", entry.Path);
                Safety.Validate(entry);
                item.Pending = true;
                // Intent is durable before any Shell operation. A write failure aborts cleanup.
            }
            catch (Exception e) { item.Error = Message.Error(e); }
            record.Items.Add(item); store.SaveItem(record.ID, item);
            if (item.Error != null) continue;
            try
            {
                var receipt = recycler.Recycle(entry.Path);
                item.RecyclePath = receipt.Path; item.RecycleParsingName = receipt.ParsingName;
                item.RecycleStamp = FileStamp.Read(receipt.Path); moved += entry.Bytes; item.Pending = false;
            }
            catch (Exception e)
            {
                item.Error = Message.Error(e);
                // Shell may have moved the file before a callback/receipt failed. Do not claim it stayed put.
                item.Pending = item.RecyclePath == null && !File.Exists(entry.Path);
            }
            store.SaveItem(record.ID, item);
        }
        store.SaveHeader(record); return record;
    }
    public HistoryRecord Restore(Guid recordID)
    {
        using var operationLock = store.Acquire();
        var record = store.History().First(r => r.ID == recordID);
        foreach (var item in record.Items.Where(i => i.RecyclePath != null && !i.Restored))
        {
            try
            {
                Safety.NoLinks(item.RecyclePath!); Safety.NoLinks(Path.GetDirectoryName(item.Source)!);
                if (item.RecycleStamp == null || !item.RecycleStamp.Matches(FileStamp.Read(item.RecyclePath!))) throw new KeeperException("검사 후 파일이 변경되었습니다. 다시 검사해 주세요: {0}", item.Source);
                if (File.Exists(item.Source) || Directory.Exists(item.Source)) throw new KeeperException("원래 위치에 같은 이름의 파일이 있어 덮어쓰지 않았습니다.");
                var restored = recycler.Restore(item);
                if (!File.Exists(restored)) throw new KeeperException("복원을 확인할 수 없습니다. 휴지통을 확인해 주세요.");
                item.Restored = true;
                item.Error = Safety.Same(restored, item.Source) ? null : new Message("이름 충돌로 다른 위치에 복원했습니다: {0}", restored);
            }
            catch (Exception e) { item.Error = Message.Error(e); }
            store.SaveItem(record.ID, item);
        }
        return record;
    }
}

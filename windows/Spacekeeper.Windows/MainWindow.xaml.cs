using Microsoft.Win32;
using Spacekeeper.Core;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;

namespace Spacekeeper.Windows;

public partial class MainWindow : Window
{
    internal readonly Store Store;
    Settings _settings, _draft;
    internal readonly ObservableCollection<FileRow> Rows = [];
    internal readonly List<string> Roots = [];
    internal ScanReport Report = new();
    readonly Dictionary<string, string> _keepers = [];
    internal string Page = "개요";
    string? _scannedPage;
    string _search = "";
    int _minimumMB = 100;
    bool _busy, _rendering, _updatingSelection;
    Message? _status;
    CancellationTokenSource _cancellation = new();
    internal Exception? LastError;
    static readonly string[] Pages = ["개요", "캐시 정리", "중복 파일", "대용량 파일", "설치 앱", "정기 청소", "정리 기록"];
    static readonly Brush Accent = new SolidColorBrush(Color.FromRgb(8, 127, 131));
    public MainWindow(Store store)
    {
        Store = store; _settings = store.LoadSettings(); _draft = _settings.Copy(); L.Language = _settings.Language;
        InitializeComponent(); Render();
    }
    internal void Navigate(string page)
    {
        if (_busy) return;
        Page = page; _search = "";
        if (page == "정기 청소") _draft = _settings.Copy();
        Render();
    }
    internal void ChangeLanguage(string language)
    {
        if (_busy) return;
        using (Store.Acquire()) { var saved = Store.LoadSettings(); saved.Language = language; Store.SaveSettings(saved); _settings = saved; }
        _draft.Language = language; L.Language = language; Render();
    }
    void LanguageChanged(object sender, SelectionChangedEventArgs args)
    {
        if (_rendering || LanguagePicker.SelectedItem is not ComboBoxItem item) return;
        try { ChangeLanguage((string)item.Tag); } catch (Exception e) { ShowError(e); }
    }
    void Render()
    {
        _rendering = true;
        try
        {
            Tagline.Text = L.Text("나의 Windows 정리 도구"); LanguageLabel.Text = L.Text("언어"); Privacy.Text = L.Text("파일을 외부 서버로 전송하지 않습니다.");
            LanguagePicker.Items.Clear();
            foreach (var code in L.Languages) LanguagePicker.Items.Add(new ComboBoxItem { Content = L.LanguageName(code), Tag = code, IsSelected = code == L.Language });
            Navigation.Children.Clear();
            foreach (var page in Pages)
            {
                var button = Button(page, () => Navigate(page)); button.HorizontalContentAlignment = HorizontalAlignment.Left;
                button.Padding = new Thickness(12); button.Margin = new Thickness(0, 3, 0, 3); button.BorderThickness = new Thickness(0);
                if (page == Page) { button.Background = new SolidColorBrush(Color.FromRgb(225, 240, 240)); button.Foreground = Accent; button.FontWeight = FontWeights.SemiBold; }
                Navigation.Children.Add(button);
            }
            PageTitle.Text = L.Text(Page);
            Subtitle.Text = L.Text(Page switch
            {
                "캐시 정리" => "다시 생성할 수 있는 오래된 앱 캐시를 정리하세요.", "중복 파일" => "내용이 완전히 같은 파일을 찾고, 남길 사본을 고르세요.",
                "대용량 파일" => "큰 파일부터 살펴보면 공간을 더 쉽게 정리할 수 있어요.", "정기 청소" => "정해진 시간에 오래된 캐시를 휴지통으로 옮깁니다.",
                "정리 기록" => "어떤 파일을 정리했는지 확인하고 원래 위치로 복원하세요.", "설치 앱" => "설치 앱과 시작 프로그램을 Windows 설정에서 관리하세요.", _ => "파일을 확인하고, 필요한 것만 남기세요."
            });
            Body.Content = Page switch { "개요" => Overview(), "정기 청소" => ScheduleView(), "정리 기록" => HistoryView(), "설치 앱" => AppsView(), _ => FilesView() };
            foreach (var row in Rows) row.Refresh();
            ReviewButton.Content = L.Text("선택 항목 검토"); ClearButton.Content = L.Text("선택 해제"); CancelButton.Content = L.Text("취소");
            SelectionBar.Visibility = IsFilePage ? Visibility.Visible : Visibility.Collapsed;
            Status.Text = _status?.ToString() ?? ""; UpdateSelection(); SetBusy(_busy);
        }
        finally { _rendering = false; }
    }
    bool IsFilePage => Page is "캐시 정리" or "중복 파일" or "대용량 파일";
    List<FileEntry> Selected => Rows.Where(r => r.Selected).Select(r => r.File).ToList();
    internal void SelectExtras() => SetSelection(true);
    void SetSelection(bool selected)
    {
        _updatingSelection = true;
        try { foreach (var row in Rows) row.Selected = selected && row.CanSelect; }
        finally { _updatingSelection = false; UpdateSelection(); }
    }
    void UpdateSelection()
    {
        if (_updatingSelection) return;
        var selected = Selected;
        SelectionText.Text = L.Text("{0}개 선택 · {1}", L.Number(selected.Count), L.Bytes(selected.Sum(f => f.Bytes)));
        ReviewButton.IsEnabled = !_busy && _scannedPage == Page && selected.Count > 0;
    }
    void SetBusy(bool value)
    {
        _busy = value; Navigation.IsEnabled = !value; LanguagePicker.IsEnabled = !value; Body.IsEnabled = !value; ClearButton.IsEnabled = !value;
        Progress.Visibility = value ? Visibility.Visible : Visibility.Collapsed; CancelButton.Visibility = value ? Visibility.Visible : Visibility.Collapsed; UpdateSelection();
    }
    void CancelClicked(object sender, RoutedEventArgs e) => _cancellation.Cancel();
    void ClearClicked(object sender, RoutedEventArgs e) => SetSelection(false);
    void ShowError(Exception e) { LastError = e; _status = Message.Error(e); Status.Text = _status.ToString(); MessageBox.Show(this, _status.ToString(), "Spacekeeper", MessageBoxButton.OK, MessageBoxImage.Warning); }
    static Button Button(string key, Action action)
    {
        var button = new Button { Content = L.Text(key) }; button.Click += (_, _) => action(); return button;
    }
    static TextBlock Text(string text, double size = 13, bool bold = false) => new() { Text = text, FontSize = size, FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 10) };
    static Border Card(UIElement content) => new() { Child = content, Background = Brushes.White, CornerRadius = new CornerRadius(10), Padding = new Thickness(22), Margin = new Thickness(0, 0, 0, 16) };
    static StackPanel Stack(params UIElement[] children) { var stack = new StackPanel(); foreach (var child in children) stack.Children.Add(child); return stack; }
    static WrapPanel Actions(params UIElement[] children) { var panel = new WrapPanel(); foreach (var child in children) panel.Children.Add(child); return panel; }
    static ScrollViewer Scroll(UIElement child) => new() { Content = child, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    static void Open(string target) => Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
    static void Reveal(string path)
    {
        var start = new ProcessStartInfo("explorer.exe") { UseShellExecute = false }; start.ArgumentList.Add("/select," + path); Process.Start(start);
    }
    UIElement Overview()
    {
        var drive = new DriveInfo(Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile))!);
        var capacity = drive.TotalSize; var free = drive.AvailableFreeSpace;
        var info = Stack(Text(L.Text("Windows 저장 공간"), 16), Text(L.Bytes(free) + " " + L.Text("사용 가능"), 36, true),
            new ProgressBar { Value = (double)(capacity - free) / capacity * 100, Maximum = 100, Height = 14, Foreground = Accent, Margin = new Thickness(0, 14, 0, 14) },
            Text(L.Text("사용 중 {0}", L.Bytes(capacity - free)) + "     " + L.Text("전체 {0}", L.Bytes(capacity))));
        var review = Card(Stack(Text(L.Text("되돌릴 수 있는 정리"), 20, true),
            Text(L.Text("선택한 파일은 휴지통으로 이동합니다. 정리 기록에서 복원할 수 있어요.")),
            Actions(Button("캐시 정리", () => Navigate("캐시 정리")), Button("중복 파일", () => Navigate("중복 파일")), Button("대용량 파일", () => Navigate("대용량 파일")))));
        var scheduled = Card(Stack(Text(L.Text("자동으로, 조심스럽게"), 20, true), Text(L.Text(_settings.ScheduleEnabled ? "정기 캐시 청소가 켜져 있습니다" : "정기 캐시 청소를 설정하세요")),
            Text(L.Text("최근 사용한 캐시와 실행 중인 앱은 보관합니다.")), Button("설정 열기", () => Navigate("정기 청소"))));
        return Scroll(Stack(Card(info), review, scheduled));
    }
    void ChooseFolders(bool exclude = false)
    {
        var dialog = new OpenFolderDialog { Multiselect = true, Title = L.Text(exclude ? "검사에서 제외" : "검사 폴더 추가") };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            if (exclude) _draft.Exclusions = _draft.Exclusions.Concat(dialog.FolderNames).Distinct(Safety.Comparer).ToList();
            else
            {
                foreach (var folder in dialog.FolderNames) { Safety.Root(folder); if (!Roots.Contains(folder, Safety.Comparer)) Roots.Add(folder); }
                _scannedPage = null; Rows.Clear();
            }
            Render();
        }
        catch (Exception error) { ShowError(error); }
    }
    UIElement FilesView()
    {
        var grid = new Grid(); grid.RowDefinitions.Add(new() { Height = GridLength.Auto }); grid.RowDefinitions.Add(new() { Height = new GridLength(1, GridUnitType.Star) });
        var controls = new StackPanel();
        if (Page != "캐시 정리")
        {
            var folders = Stack(Text(L.Text("검사할 폴더"), 16, true), Button("폴더 추가", () => ChooseFolders()));
            foreach (var folder in Roots.ToArray())
            {
                var line = new DockPanel(); var remove = Button("검사 폴더에서 제외", () => { Roots.Remove(folder); Rows.Clear(); _scannedPage = null; Render(); });
                DockPanel.SetDock(remove, Dock.Right); line.Children.Add(remove); line.Children.Add(Text(folder)); folders.Children.Add(line);
            }
            controls.Children.Add(Card(folders));
        }
        else controls.Children.Add(Text(L.Text("최근 {0}일 동안 수정하거나 사용한 캐시는 보관합니다. 브라우저 방문 기록·쿠키·비밀번호는 정리 대상에 포함하지 않습니다.", L.Number(_settings.MinimumDays))));
        var actions = Actions(Button(_scannedPage == Page ? "다시 검사" : "검사 시작", async () => await ScanAsync()));
        if (Page == "대용량 파일")
        {
            var minimum = new ComboBox { ItemsSource = new[] { 10, 100, 500, 1024 }, SelectedItem = _minimumMB, Width = 100 };
            minimum.SelectionChanged += (_, _) => { _minimumMB = (int)minimum.SelectedItem; _scannedPage = null; Rows.Clear(); Render(); };
            actions.Children.Add(Text(L.Text("최소 파일 크기") + " (MB)")); actions.Children.Add(minimum);
        }
        else actions.Children.Add(Button(Page == "중복 파일" ? "추가 사본 선택" : "가능한 캐시 선택", SelectExtras));
        controls.Children.Add(actions);
        var search = new TextBox { Text = _search, ToolTip = L.Text("파일 이름 또는 경로 검색"), Margin = new Thickness(0, 8, 0, 12) };
        search.TextChanged += (_, _) => { _search = search.Text; CollectionViewSource.GetDefaultView(Rows).Refresh(); };
        controls.Children.Add(Text(L.Text("파일 이름 또는 경로 검색"), 12)); controls.Children.Add(search);
        if (_scannedPage == Page)
        {
            controls.Children.Add(Text(L.Text("{0}개 파일", L.Number(Report.Files.Count)) + (Page == "중복 파일" ? "  /  " + L.Text("{0}개 중복 그룹", L.Number(Report.Groups.Count)) : "")));
            if (Report.Truncated) controls.Children.Add(Text(L.Text("20만 항목 제한에 도달했습니다. 폴더를 좁혀서 다시 검사해 주세요. 아래는 일부 결과입니다.")));
            if (Report.Issues.Count > 0) controls.Children.Add(new Expander { Header = L.Text("확인할 항목 {0}개", L.Number(Report.Issues.Count)), Content = new ListBox { ItemsSource = Report.Issues.Select(m => m.ToString()), MaxHeight = 120 } });
        }
        grid.Children.Add(controls);
        if (_scannedPage != Page)
        { var empty = Text(L.Text("검사할 항목을 선택해 주세요."), 19); empty.VerticalAlignment = VerticalAlignment.Center; empty.HorizontalAlignment = HorizontalAlignment.Center; Grid.SetRow(empty, 1); grid.Children.Add(empty); return grid; }
        var table = new DataGrid { ItemsSource = Rows, SelectionMode = DataGridSelectionMode.Single };
        var check = new FrameworkElementFactory(typeof(CheckBox)); check.SetBinding(CheckBox.IsCheckedProperty, new Binding(nameof(FileRow.Selected)) { Mode = BindingMode.TwoWay, UpdateSourceTrigger = UpdateSourceTrigger.PropertyChanged });
        check.SetBinding(IsEnabledProperty, new Binding(nameof(FileRow.CanSelect))); check.SetValue(HorizontalAlignmentProperty, HorizontalAlignment.Center); check.SetValue(VerticalAlignmentProperty, VerticalAlignment.Center);
        table.Columns.Add(new DataGridTemplateColumn { Header = "✓", Width = 40, CellTemplate = new DataTemplate { VisualTree = check } });
        Column(table, "파일 이름", nameof(FileRow.Name), 180); Column(table, "경로", nameof(FileRow.Path), 1, star: true); Column(table, "크기", nameof(FileRow.Size), 95);
        if (Page == "중복 파일")
        {
            Column(table, "그룹", nameof(FileRow.GroupLabel), 85);
            var keep = new FrameworkElementFactory(typeof(Button)); keep.SetValue(ContentControl.ContentProperty, L.Text("이 사본 보관"));
            keep.AddHandler(System.Windows.Controls.Button.ClickEvent, new RoutedEventHandler((sender, _) => { var row = (FileRow)((Button)sender).DataContext; Keep(row); }));
            table.Columns.Add(new DataGridTemplateColumn { Header = L.Text("보관"), Width = 135, CellTemplate = new DataTemplate { VisualTree = keep } });
        }
        var reveal = new FrameworkElementFactory(typeof(Button)); reveal.SetValue(ContentControl.ContentProperty, "↗"); reveal.SetValue(ToolTipProperty, L.Text("탐색기에서 보기"));
        reveal.AddHandler(System.Windows.Controls.Button.ClickEvent, new RoutedEventHandler((sender, _) => Reveal(((FileRow)((Button)sender).DataContext).Path)));
        table.Columns.Add(new DataGridTemplateColumn { Width = 55, CellTemplate = new DataTemplate { VisualTree = reveal } });
        CollectionViewSource.GetDefaultView(Rows).Filter = item => item is FileRow row && (string.IsNullOrEmpty(_search) || row.Path.Contains(_search, StringComparison.OrdinalIgnoreCase));
        Grid.SetRow(table, 1); grid.Children.Add(table); return grid;
    }
    static void Column(DataGrid table, string title, string property, double width, bool star = false) => table.Columns.Add(new DataGridTextColumn
        { Header = L.Text(title), Binding = new Binding(property), IsReadOnly = true, Width = new DataGridLength(width, star ? DataGridLengthUnitType.Star : DataGridLengthUnitType.Pixel) });
    internal void Keep(FileRow row)
    {
        if (row.GroupID == null) return;
        _keepers[row.GroupID] = row.Path;
        foreach (var item in Rows.Where(r => r.GroupID == row.GroupID)) { item.CanSelect = item.Path != row.Path; if (!item.CanSelect) item.Selected = false; item.Refresh(); }
        UpdateSelection();
    }
    internal async Task ScanAsync()
    {
        if (_busy) return;
        if (Page != "캐시 정리" && Roots.Count == 0) { ChooseFolders(); if (Roots.Count == 0) return; }
        LastError = null; _cancellation = new(); SetBusy(true); var page = Page;
        var lastProgress = Stopwatch.StartNew();
        void ProgressChanged(Message message) { if (lastProgress.ElapsedMilliseconds < 150) return; lastProgress.Restart(); Dispatcher.BeginInvoke(() => { _status = message; Status.Text = message.ToString(); }); }
        try
        {
            var settings = _settings.Copy(); var roots = Roots.ToArray(); var minimum = _minimumMB;
            Report = await Task.Run(() =>
            {
                if (page == "캐시 정리") return CacheRules.Scan(settings, _cancellation.Token, ProgressChanged);
                var report = Scanner.Walk(roots, _cancellation.Token, page == "대용량 파일" ? minimum * 1024L * 1024 : 1, settings.Exclusions, progress: ProgressChanged);
                if (page == "중복 파일") Scanner.FindDuplicates(report, _cancellation.Token, ProgressChanged);
                return report;
            });
            Rows.Clear(); _keepers.Clear();
            if (page == "중복 파일")
            {
                var i = 0;
                foreach (var group in Report.Groups)
                {
                    _keepers[group.ID] = group.Files[0].Path; i++;
                    foreach (var file in group.Files) AddRow(new(file) { GroupID = group.ID, GroupNumber = i, CanSelect = file.Path != group.Files[0].Path });
                }
            }
            else foreach (var file in Report.Files.OrderByDescending(f => f.Bytes)) AddRow(new(file));
            _scannedPage = page; _status = new("검사 완료");
        }
        catch (OperationCanceledException) { _status = new("검사를 취소했습니다."); }
        catch (Exception e) { LastError = e; _status = Message.Error(e); }
        finally { SetBusy(false); Render(); }
    }
    void AddRow(FileRow row) { row.PropertyChanged += (_, e) => { if (e.PropertyName == nameof(FileRow.Selected)) UpdateSelection(); }; Rows.Add(row); }
    async void ReviewClicked(object sender, RoutedEventArgs e)
    {
        var selected = Selected; if (selected.Count == 0) return;
        var dialog = new Window { Owner = this, Title = L.Text("휴지통으로 이동하기 전 확인"), Width = 760, Height = 520, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        var panel = new DockPanel { Margin = new Thickness(24) };
        var header = Stack(Text(L.Text("{0}개 파일 · {1}", L.Number(selected.Count), L.Bytes(selected.Sum(f => f.Bytes))), 22, true), Text(L.Text("파일을 확인해 주세요. 정리 기록에서 복원할 수 있으며, 휴지통을 비우기 전까지는 디스크 공간을 차지합니다.")));
        DockPanel.SetDock(header, Dock.Top); panel.Children.Add(header);
        var buttons = Actions(Button("취소", () => dialog.DialogResult = false), Button("휴지통으로 이동", () => dialog.DialogResult = true));
        buttons.HorizontalAlignment = HorizontalAlignment.Right; DockPanel.SetDock(buttons, Dock.Bottom); panel.Children.Add(buttons);
        panel.Children.Add(new ListBox { ItemsSource = selected.Select(f => f.Path + "   " + L.Bytes(f.Bytes)) }); dialog.Content = panel;
        if (dialog.ShowDialog() == true) await CleanSelectionAsync();
    }
    internal async Task CleanSelectionAsync()
    {
        LastError = null; _cancellation = new(); SetBusy(true);
        var request = new CleanupRequest(Page == "중복 파일" ? CleanupKind.Duplicates : Page == "캐시 정리" ? CleanupKind.Cache : CleanupKind.Large, Selected, Report.Groups, _settings.MinimumDays);
        try
        {
            var result = await Sta.Run(() => new Cleaner(Store, new WindowsRecycler()).Clean(request, _cancellation.Token));
            _status = new("휴지통 이동 {0}개 · {1}", L.Number(result.MovedCount), L.Bytes(result.MovedBytes)); Rows.Clear(); _scannedPage = null; Page = "정리 기록";
        }
        catch (Exception e) { LastError = e; _status = Message.Error(e); }
        finally { SetBusy(false); Render(); }
    }
    internal async Task RestoreAsync(Guid id)
    {
        LastError = null; _cancellation = new(); SetBusy(true);
        try { await Sta.Run(() => new Cleaner(Store, new WindowsRecycler()).Restore(id, _cancellation.Token)); _status = new(_cancellation.IsCancellationRequested ? "남은 작업을 취소했습니다." : "복원 작업 완료"); Rows.Clear(); _scannedPage = null; }
        catch (Exception e) { LastError = e; _status = Message.Error(e); }
        finally { SetBusy(false); Render(); }
    }
    UIElement HistoryView()
    {
        var panel = Stack(Text(L.Text("휴지통으로 옮긴 파일은 아직 디스크 공간을 차지합니다. 정리를 확인한 뒤 Windows 휴지통을 비우세요. 비운 파일은 복원할 수 없습니다.")),
            Actions(Button("휴지통 열기", () => Open("shell:RecycleBinFolder")), Button("새로 고침", Render)));
        try
        {
            var records = Store.History(); if (records.Count == 0) panel.Children.Add(Text(L.Text("아직 정리 기록이 없습니다"), 20));
            foreach (var record in records)
            {
                var restore = Button("복원", async () =>
                {
                    if (MessageBox.Show(this, L.Text("휴지통에 남아 있는 파일을 복원합니다. 같은 이름의 파일이 있으면 덮어쓰지 않습니다."), L.Text("원래 위치로 복원할까요?"), MessageBoxButton.OKCancel) == MessageBoxResult.OK) await RestoreAsync(record.ID);
                }); restore.IsEnabled = record.MovedCount > 0;
                var details = record.Items.Select(i => (i.Restored ? L.Text("복원됨") : i.RecyclePath != null ? L.Text("휴지통으로 이동") : i.Pending ? L.Text("처리 중단 · 탐색기에서 확인") : L.Text("이동되지 않음")) + "  " + i.Source + (i.Error == null ? "" : "\n" + i.Error));
                panel.Children.Add(Card(Stack(Text(L.Text(record.Kind), 18, true), Text(L.Date(record.Date)), Text(L.Text("휴지통 이동 {0}개 · {1}", L.Number(record.MovedCount), L.Bytes(record.MovedBytes))),
                    Text(record.Note?.ToString() ?? ""), restore, new Expander { Header = L.Text("파일 상세 {0}개", L.Number(record.Items.Count)), Content = new ListBox { ItemsSource = details, MaxHeight = 260 } })));
            }
        }
        catch (Exception e) { panel.Children.Add(Text(Message.Error(e).ToString())); }
        return Scroll(panel);
    }
    UIElement AppsView()
    {
        var grid = new DockPanel(); var actions = Actions(Button("설치 앱 설정", () => Open("ms-settings:appsfeatures")), Button("시작 프로그램 설정", () => Open("ms-settings:startupapps")));
        DockPanel.SetDock(actions, Dock.Top); grid.Children.Add(actions);
        var table = new DataGrid { IsReadOnly = true, ItemsSource = InstalledApps.Read() };
        Column(table, "설치 앱", nameof(InstalledApp.Name), 1, true); Column(table, "버전", nameof(InstalledApp.Version), 150); Column(table, "경로", nameof(InstalledApp.Location), 1, true);
        grid.Children.Add(table); return grid;
    }
    UIElement ScheduleView()
    {
        var panel = new StackPanel();
        var enabled = new CheckBox { Content = L.Text("정기 청소 사용"), IsChecked = _draft.ScheduleEnabled, FontSize = 18, Margin = new Thickness(0, 0, 0, 18) };
        enabled.Checked += (_, _) => _draft.ScheduleEnabled = true; enabled.Unchecked += (_, _) => _draft.ScheduleEnabled = false; panel.Children.Add(enabled);
        void Picker<T>(string label, IEnumerable<(string Name, T Value)> values, T value, Action<T> changed)
        {
            var combo = new ComboBox { Width = 190 };
            foreach (var pair in values) combo.Items.Add(new ComboBoxItem { Content = pair.Name, Tag = pair.Value, IsSelected = EqualityComparer<T>.Default.Equals(pair.Value, value) });
            combo.SelectionChanged += (_, _) => { if (combo.SelectedItem is ComboBoxItem item) changed((T)item.Tag); };
            panel.Children.Add(Actions(new TextBlock { Text = L.Text(label), Width = 190, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap }, combo));
        }
        Picker("청소 주기", new[] { (L.Text("매주"), false), (L.Text("매일"), true) }, _draft.Daily, v => _draft.Daily = v);
        string[] days = ["일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"];
        Picker("요일", days.Select((d, i) => (L.Text(d), i)), _draft.Weekday, v => _draft.Weekday = v);
        Picker("시", Enumerable.Range(0, 24).Select(i => (i.ToString("00"), i)), _draft.Hour, v => _draft.Hour = v);
        Picker("분", Enumerable.Range(0, 60).Select(i => (i.ToString("00"), i)), _draft.Minute, v => _draft.Minute = v);
        Picker("캐시 보관 기간", new[] { 7, 14, 30, 90 }.Select(i => (L.Text(i + "일"), i)), _draft.MinimumDays, v => _draft.MinimumDays = v);
        Picker("1회 정리 한도", new[] { 500L * 1024 * 1024, 2L * 1024 * 1024 * 1024, 5L * 1024 * 1024 * 1024 }.Select(i => (L.Bytes(i), i)), _draft.MaximumBytes, v => _draft.MaximumBytes = v);
        panel.Children.Add(Text(L.Text("청소할 앱 캐시"), 18, true));
        foreach (var (id, name) in new[] { ("chrome", "Chrome"), ("edge", "Edge"), ("brave", "Brave"), ("firefox", "Firefox"), ("spotify", "Spotify"), ("vscode", "VS Code") })
        {
            var check = new CheckBox { Content = name, IsChecked = _draft.CacheIDs.Contains(id), Margin = new Thickness(0, 5, 0, 5) };
            check.Checked += (_, _) => _draft.CacheIDs.Add(id); check.Unchecked += (_, _) => _draft.CacheIDs.Remove(id); panel.Children.Add(check);
        }
        panel.Children.Add(Text(L.Text("검사·정리에서 제외할 폴더"), 18, true)); panel.Children.Add(Button("폴더 추가", () => ChooseFolders(true)));
        foreach (var path in _draft.Exclusions.ToArray()) panel.Children.Add(Actions(Text(path), Button("제외 해제", () => { _draft.Exclusions.Remove(path); Render(); })));
        panel.Children.Add(Text(L.Text("로그인한 동안 앱을 종료해도 예약이 실행됩니다. 앱을 이동했다면 설정을 다시 저장하세요. 중복 파일은 자동으로 정리하지 않습니다.")));
        panel.Children.Add(Button("설정 저장", async () =>
        {
            SetBusy(true);
            try { var draft = _draft.Copy(); await Task.Run(() => Scheduler.Apply(draft, Store, Environment.ProcessPath!)); _settings = draft; _status = new("설정 저장 완료"); }
            catch (Exception e) { _status = Message.Error(e); _settings = Store.LoadSettings(); }
            finally { SetBusy(false); Render(); }
        }));
        return Scroll(Card(panel));
    }
}

public sealed class FileRow(FileEntry file) : INotifyPropertyChanged
{
    public FileEntry File { get; } = file;
    public string Name => File.Name;
    public string Path => File.Path;
    public string Size => L.Bytes(File.Bytes);
    public string? GroupID { get; set; }
    public int GroupNumber { get; set; }
    public string GroupLabel => (CanSelect ? "" : "✓ ") + L.Number(GroupNumber);
    bool _selected;
    public bool Selected { get => _selected; set { var next = CanSelect && value; if (_selected == next) return; _selected = next; PropertyChanged?.Invoke(this, new(nameof(Selected))); } }
    public bool CanSelect { get; set; } = true;
    public event PropertyChangedEventHandler? PropertyChanged;
    public void Refresh() => PropertyChanged?.Invoke(this, new(null));
}

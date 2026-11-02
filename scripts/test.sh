#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
TEST_BUILD="$PROJECT_DIR/codex-work/test-build"
mkdir -p "$TEST_BUILD/module-cache"
swiftc -swift-version 5 -module-cache-path "$TEST_BUILD/module-cache" \
  -emit-library -emit-module -enable-testing -module-name SpacekeeperCore \
  Sources/SpacekeeperCore/*.swift -o "$TEST_BUILD/libSpacekeeperCore.dylib" \
  -emit-module-path "$TEST_BUILD/SpacekeeperCore.swiftmodule"
python3 - "$PROJECT_DIR" "$TEST_BUILD" <<'PY'
import pathlib, re, sys
project, build = map(pathlib.Path, sys.argv[1:])
source = (project / 'Tests/SpacekeeperCoreTests/SafetyTests.swift').read_text()
names = re.findall(r'func (test\w+)\(\) throws', source)
calls = ',\n'.join(f'("{name}", {{ try $0.{name}() }})' for name in names)
runner = '''import Foundation
let tests: [(String, (SafetyTests) throws -> Void)] = [
CALLS
]
for (name, test) in tests {
    let instance = SafetyTests()
    let before = failures
    do { try instance.setUpWithError(); try test(instance) }
    catch { failures += 1; print("FAIL \\(name): \\(error)") }
    do { try instance.tearDownWithError() }
    catch { failures += 1; print("FAIL cleanup: \\(error)") }
    if failures == before { print("PASS \\(name)") }
}
print("\\(tests.count) tests; \\(failures) failures")
exit(failures == 0 ? 0 : 1)
'''.replace('CALLS', calls)
(build / 'main.swift').write_text(runner)
PY
swiftc -swift-version 5 -D STANDALONE_TESTS -module-cache-path "$TEST_BUILD/module-cache" \
  -I "$TEST_BUILD" -L "$TEST_BUILD" -lSpacekeeperCore -Xlinker -rpath -Xlinker "$TEST_BUILD" \
  scripts/TestSupport.swift "$PROJECT_DIR/Tests/SpacekeeperCoreTests/SafetyTests.swift" "$TEST_BUILD/main.swift" \
  -o "$TEST_BUILD/SafetyTests"
"$TEST_BUILD/SafetyTests"

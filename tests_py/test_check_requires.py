"""Self-test that source require checker catches missing imports without Luau."""
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from check_requires import check


class RequireCheckerTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        (self.root / 'src/server').mkdir(parents=True)
        (self.root / 'src/shared/Data').mkdir(parents=True)
        (self.root / 'src/map').mkdir(parents=True)
        (self.root / 'src/server/B.luau').write_text('return true', encoding='utf-8')
        (self.root / 'src/shared/Data/C.luau').write_text('return true', encoding='utf-8')
        (self.root / 'src/map/Map.luau').write_text('return true', encoding='utf-8')

    def test_valid_references(self):
        (self.root / 'src/server/A.luau').write_text('''
local b = require(script.Parent.B)
local c = Link.shared("Data/C")
local m = require(mapFolder:WaitForChild("Map"))
''', encoding='utf-8')
        issues, local, shared, maps, unknown = check(self.root)
        self.assertEqual(issues, [])
        self.assertEqual((local, shared, maps, unknown), (1, 1, 1, 0))

    def test_fails_missing_local(self):
        (self.root / 'src/server/A.luau').write_text('require(script.Parent.NotHere)', encoding='utf-8')
        self.assertIn('NotHere', '\n'.join(check(self.root)[0]))

    def test_fails_missing_shared(self):
        (self.root / 'src/server/A.luau').write_text('Link.shared("Data/Missing")', encoding='utf-8')
        self.assertIn('Data/Missing', '\n'.join(check(self.root)[0]))

    def test_fails_missing_map(self):
        (self.root / 'src/server/A.luau').write_text('require(mapFolder:WaitForChild("Missing"))', encoding='utf-8')
        self.assertIn('Missing', '\n'.join(check(self.root)[0]))


if __name__ == '__main__':
    unittest.main()

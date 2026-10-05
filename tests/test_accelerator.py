import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('accelerator', Path(__file__).resolve().parents[1] / 'src/accelerator.py')
accelerator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(accelerator)

class AcceleratorTests(unittest.TestCase):
    def test_connlimit_sets_have_no_timeout_and_patch_is_idempotent(self):
        text = '\n'.join('meter '+name+' { '+family+' saddr ct count over ${CONN_LIMIT} } drop'
                         for name, family in [('cc4_${p}', 'ip'), ('cc6_${p}', 'ip6'), ('occ4', 'ip'), ('occ6', 'ip6')])
        text += '\n    rate_set "syn4_${p}" ipv4_addr\n$RATE_SETS\n'
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'protect.sh'
            path.write_text(text)
            accelerator.patch_protect(path)
            updated = path.read_text()
            self.assertNotIn('meter ', updated)
            self.assertEqual(updated.count('ct count over'), 4)
            self.assertEqual(updated.count('flags dynamic; }'), 4)
            self.assertNotIn('timeout;', updated)
            accelerator.patch_protect(path)
            self.assertEqual(updated, path.read_text())

    def test_unknown_upstream_is_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'protect.sh'
            path.write_text('unrecognized upstream')
            with self.assertRaises(ValueError):
                accelerator.patch_protect(path)
            self.assertEqual(path.read_text(), 'unrecognized upstream')

import importlib.util,ipaddress,os,tempfile,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('config',Path(__file__).resolve().parents[1]/'src/config.py');c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
class ConfigTests(unittest.TestCase):
 def test_validation(self):
  for value in ['0','65536','443;touch /tmp/x','443,']:
   with self.assertRaises(ValueError): c.validate({'tcp_ports':value})
  with self.assertRaises(ValueError): c.validate({'node_domain':'example.org;id'})
  with self.assertRaises(ValueError): c.validate({'whitelist':'999.1.1.1'})
 def test_no_udp(self):
  c.validate({'udp_ports':'none'})
  for value in ['', 'none,443', 'n']:
   with self.assertRaises(ValueError):c.validate({'udp_ports':value})
  c.validate({'tcp_ports':'none'})
 def test_secret_and_permissions(self):
  with tempfile.TemporaryDirectory() as d:
   p=d+'/config.json';c.atomic(p,{'node_secret':'abc\ndef==','role':'node'})
   self.assertEqual(os.stat(p).st_mode&0o777,0o600)
 def test_subtraction(self):
  import contextlib,io
  with tempfile.NamedTemporaryFile(mode='w') as f:
   f.write('10.0.0.0/24\n2001:db8::/120\n');f.flush();out=io.StringIO()
   with contextlib.redirect_stdout(out): c.subtract(f.name,'10.0.0.8,2001:db8::1')
  nets=[ipaddress.ip_network(x) for x in out.getvalue().splitlines() if x]
  for addr in ['10.0.0.8','2001:db8::1']: self.assertFalse(any(ipaddress.ip_address(addr) in n for n in nets))
  for addr in ['10.0.0.9','2001:db8::2']: self.assertTrue(any(ipaddress.ip_address(addr) in n for n in nets))
if __name__=='__main__': unittest.main()

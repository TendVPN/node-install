import json,os,subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CLI=str(ROOT/'src/tend.sh')
class CLITests(unittest.TestCase):
 def runcli(self,args,env=None): return subprocess.run(['bash',CLI,*args],capture_output=True,text=True,env=env)
 def test_missing_node_data(self):
  with tempfile.TemporaryDirectory() as d:
   r=self.runcli(['plan','--config',d+'/absent','--non-interactive'])
  self.assertNotEqual(r.returncode,0);self.assertIn('--node-domain',r.stderr)
 def test_profile_override_and_no_secret_leak(self):
  with tempfile.TemporaryDirectory() as d:
   p=d+'/defaults.json';Path(p).write_text(json.dumps({'role':'node','node_domain':'node.example.org','panel_ip':'203.0.113.1','email':'a@example.org','node_secret':'PRIVATE_SECRET','ssh_port':'22224'}))
   r=self.runcli(['plan','--config',p,'--ssh-port=22225','--non-interactive'])
  self.assertEqual(r.returncode,0,r.stderr);self.assertIn('22225',r.stdout);self.assertNotIn('22224',r.stdout);self.assertNotIn('PRIVATE_SECRET',r.stdout)
 def test_service_without_home(self):
  env=dict(os.environ);env.pop('HOME',None);env['TEND_CONFIG']='/nonexistent/tend-test.json'
  r=self.runcli(['plan','--node-domain','node.example.org','--panel-ip','203.0.113.1','--node-secret-file',str(ROOT/'tests/node-key-fixture.txt'),'--email','admin@example.org','--non-interactive'],env)
  self.assertEqual(r.returncode,0,r.stderr)
 def test_invalid_input_before_mutation(self):
  with tempfile.TemporaryDirectory() as d:
   r=self.runcli(['plan','--config',d+'/absent','--node-domain','node.example.org','--panel-ip','203.0.113.1','--node-secret-file',str(ROOT/'tests/node-key-fixture.txt'),'--email','admin@example.org','--ssh-port','70000','--non-interactive'])
  self.assertNotEqual(r.returncode,0);self.assertIn('Неверный порт',r.stderr)
if __name__=='__main__': unittest.main()

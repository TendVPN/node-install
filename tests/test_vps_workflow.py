import json,os,pty,select,signal,subprocess,tarfile,tempfile,time,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class VPSWorkflowTests(unittest.TestCase):
 def test_flags_without_subcommand(self):
  with tempfile.TemporaryDirectory() as d:
   r=subprocess.run(['bash',str(ROOT/'src/tend.sh'),'--node-domain','node.example.org','--panel-ip','203.0.113.1','--node-secret-file',str(ROOT/'tests/node-key-fixture.txt'),'--email','admin@example.org','--non-interactive','--dry-run','--config',d+'/absent'],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stderr);self.assertIn('role',r.stdout)
 def test_no_udp_flags(self):
  for value in ['n','none','N']:
   with tempfile.TemporaryDirectory() as d:
    r=subprocess.run(['bash',str(ROOT/'src/tend.sh'),'--node-domain','node.example.org','--panel-ip','203.0.113.1','--node-secret-file',str(ROOT/'tests/node-key-fixture.txt'),'--email','admin@example.org','--tcp-ports',value,'--udp-ports',value,'--non-interactive','--dry-run','--config',d+'/absent'],capture_output=True,text=True)
   self.assertEqual(r.returncode,0,r.stderr);self.assertRegex(r.stdout,r'udp_ports\s+none');self.assertRegex(r.stdout,r'tcp_ports\s+none')
 def test_tcp_firewall_ports(self):
  for role,ports,expected in [('node','none','80'),('node','443,8443','80,443,8443')]:
   script='source "$1"; declare -A C=([role]="$2" [tcp_ports]="$3"); service_tcp_ports'
   r=subprocess.run(['bash','-c',script,'test',str(ROOT/'src/server.sh'),role,ports],capture_output=True,text=True)
   self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(r.stdout,expected)
 def test_only_node_role_and_flags(self):
  for role in ['panel','panel-sub','panel-node-sub','sub','none']:
   with tempfile.TemporaryDirectory() as d:
    r=subprocess.run(['bash',str(ROOT/'src/tend.sh'),'--role',role,'--non-interactive','--dry-run','--config',d+'/absent'],capture_output=True,text=True)
   self.assertNotEqual(r.returncode,0);self.assertIn('--role node',r.stderr)
  for flag in ['--panel-domain','--sub-domain','--sub-token','--panel-cookie']:
   r=subprocess.run(['bash',str(ROOT/'src/tend.sh'),flag,'unused','--dry-run'],env=dict(os.environ,TEND_CONFIG='/nonexistent/tend-test.json'),capture_output=True,text=True)
   self.assertNotEqual(r.returncode,0);self.assertIn('Неизвестный флаг',r.stderr)
 def test_removed_commands(self):
  for command in ['deploy','client-menu']:
   r=subprocess.run(['bash',str(ROOT/'src/tend.sh'),command],capture_output=True,text=True)
   self.assertNotEqual(r.returncode,0);self.assertIn('Неизвестная команда',r.stderr)
 def test_wizard_skips_flags_and_disables_udp(self):
  with tempfile.TemporaryDirectory() as d:
   pid,fd=pty.fork()
   if pid==0:
    os.environ.update(TERM='xterm',TEND_CONFIG=d+'/absent');os.environ.pop('NO_COLOR',None)
    os.execvp('bash',['bash',str(ROOT/'src/tend.sh'),'install','--dry-run','--node-domain','node.example.org','--panel-ip','203.0.113.1','--node-secret-file',str(ROOT/'tests/node-key-fixture.txt'),'--email','admin@example.org','--optimize','no'])
   out=b'';sent=False;status=None;deadline=time.monotonic()+10
   try:
    while time.monotonic()<deadline:
     if select.select([fd],[],[],.1)[0]:
      try:part=os.read(fd,65536)
      except OSError:break
      if not part:break
      out+=part
      if not sent and 'Ответ ['.encode() in out:
       os.write(fd,('\n'.join(['','n','n','n','','','','','',''])+'\n').encode());sent=True
     done,status=os.waitpid(pid,os.WNOHANG)
     if done:break
    if status is None or not done:os.kill(pid,signal.SIGKILL);_,status=os.waitpid(pid,0)
   finally:os.close(fd)
   text=out.decode(errors='replace')
   self.assertEqual(os.waitstatus_to_exitcode(status),0,text)
   self.assertIn('Пример ответа: 22223',text);self.assertIn('\x1b[',text)
   self.assertNotIn('Что установить на этом VPS?',text);self.assertNotIn('Оптимизация VPS',text)
   self.assertIn('[Tend-Menu]:',text);self.assertRegex(text,r'tcp_ports\s+none');self.assertIn('Ответ [Y/n]',text);self.assertRegex(text,r'udp_ports\s+none')
   self.assertRegex(text,r'protect\s+no');self.assertRegex(text,r'optimize\s+no')
 def test_bootstrap_forwards_flags_without_installing(self):
  with tempfile.TemporaryDirectory() as d:
   base=Path(d);archive=base/'source.tgz'
   with tarfile.open(archive,'w:gz') as t:
    for name in ['src','vendor','upstream-lock.json']:t.add(ROOT/name,arcname='project/'+name)
   mock=base/'mock';mock.mkdir()
   (mock/'id').write_text('#!/bin/sh\necho 0\n');(mock/'id').chmod(0o755)
   (mock/'curl').write_text('#!'+os.sys.executable+'\nimport os,shutil,sys\nshutil.copyfile(os.environ["TEND_TEST_ARCHIVE"],sys.argv[-1])\n');(mock/'curl').chmod(0o755)
   env=dict(os.environ,PATH=str(mock)+':'+os.environ['PATH'],TEND_TEST_ARCHIVE=str(archive),TEND_CONFIG=str(base/'absent'))
   r=subprocess.run(['sh',str(ROOT/'install.sh'),'--node-domain','node.example.org','--panel-ip','203.0.113.1','--node-secret-file',str(ROOT/'tests/node-key-fixture.txt'),'--email','admin@example.org','--non-interactive','--dry-run'],env=env,capture_output=True,text=True)
   self.assertEqual(r.returncode,0,r.stderr);self.assertIn('Параметры установки',r.stdout)
if __name__=='__main__':unittest.main()

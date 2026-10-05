#!/usr/bin/env python3
"""JSON configuration, input validation and network-list subtraction. No eval."""
import ipaddress,json,os,re,sys,tempfile
FIELDS={'role','email','node_domain','panel_ip','node_secret','disable_password_auth','ssh_port','tcp_ports','udp_ports','regions','whitelist','optimize','protect','traffic_guard','psiphon','multitest','xanmod','guard_urls'}
def validate(c):
    unknown=set(c)-FIELDS
    if unknown: raise ValueError('Неизвестные настройки: '+', '.join(sorted(unknown)))
    for k,v in c.items():
        if not isinstance(v,str) or '\x00' in v: raise ValueError('Неверный тип: '+k)
        if k!='node_secret' and ('\n' in v or '\r' in v): raise ValueError('Перенос строки: '+k)
        if k in ('ssh_port','tcp_ports','udp_ports') and not (k in ('tcp_ports','udp_ports') and v=='none'):
            for p in v.split(','):
                if not p.isdigit() or not 1<=int(p)<=65535: raise ValueError('Неверный порт: '+k)
        if k in ('disable_password_auth','optimize','protect','traffic_guard','psiphon','multitest','xanmod') and v not in ('yes','no'): raise ValueError(k+': yes/no')
        if k=='role' and v!='node': raise ValueError('Допустимое значение role: node')
        if k.endswith('_domain') and v and (len(v)>253 or not re.fullmatch(r'(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}',v)): raise ValueError('Неверный домен: '+k)
        if k=='email' and v and not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+',v): raise ValueError('Неверный email')
        if k=='panel_ip' and v: ipaddress.IPv4Address(v)
        if k=='whitelist' and v:
            for ip in v.split(','): ipaddress.ip_network(ip,strict=False)
        if k=='regions' and not re.fullmatch(r'[A-Z]{2}(,[A-Z]{2})*',v): raise ValueError('Регионы: DE,NL,FR')
        if k=='guard_urls':
            for u in v.split(','):
                if not u.startswith('https://') or any(x.isspace() for x in u): raise ValueError('Списки: только HTTPS')
        if k=='node_secret' and v and (not re.fullmatch(r'[A-Za-z0-9+/=\s._:-]+',v) or '$' in v): raise ValueError('Неверный secret ноды')
    if c.get('ssh_port')=='2222': raise ValueError('SSH 2222 конфликтует с node-agent')
    if c.get('ssh_port') in c.get('tcp_ports','').split(','): raise ValueError('SSH-порт совпадает с сервисным TCP-портом')
    return c

def atomic(path,data):
    os.makedirs(os.path.dirname(os.path.abspath(path)),mode=0o700,exist_ok=True)
    fd,tmp=tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)))
    try:
        with os.fdopen(fd,'w') as f: json.dump(validate(data),f,ensure_ascii=False,indent=2);f.write('\n')
        os.chmod(tmp,0o600);os.replace(tmp,path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def subtract(source,white):
    trusted=[ipaddress.ip_network(x,strict=False) for x in white.split(',') if x]
    result=[]
    with open(source) as f:
        for line in f:
            line=line.split('#')[0].strip()
            if not line: continue
            n=ipaddress.ip_network(line,strict=False);parts=[n]
            for w in trusted:
                nextparts=[]
                for p in parts:
                    if p.version!=w.version or not p.overlaps(w): nextparts.append(p)
                    elif p.subnet_of(w): pass
                    else: nextparts.extend(p.address_exclude(w))
                parts=nextparts
            result.extend(parts)
    print('\n'.join(map(str,ipaddress.collapse_addresses([x for x in result if x.version==4]))))
    print('\n'.join(map(str,ipaddress.collapse_addresses([x for x in result if x.version==6]))))

if __name__=='__main__':
    try:
        op=sys.argv[1]
        if op=='read':
            c=validate(json.load(open(sys.argv[2])))
            for k,v in c.items(): sys.stdout.buffer.write(k.encode()+b'\0'+v.encode()+b'\0')
        elif op=='write':
            raw=sys.stdin.buffer.read().split(b'\0');c={raw[i].decode():raw[i+1].decode() for i in range(0,len(raw)-1,2)};atomic(sys.argv[2],c)
        elif op=='validate': validate(json.load(open(sys.argv[2])))
        elif op=='subtract': subtract(sys.argv[2],sys.argv[3])
    except (ValueError,OSError,KeyError) as e: print('Ошибка: '+str(e),file=sys.stderr);sys.exit(2)

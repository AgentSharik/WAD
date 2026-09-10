import re, subprocess, os, concurrent.futures
root='/home/user/repo'
urls={}
for dp,_,fns in os.walk(root):
    if '.git' in dp: continue
    for fn in fns:
        if fn.endswith('.ps1') or fn=='autounattend.xml':
            p=os.path.join(dp,fn)
            txt=open(p,encoding='utf-8',errors='replace').read()
            for u in re.findall(r'https?://[^\s"\'<>\)\]]+', txt):
                u=u.rstrip('.,;').replace('`','')
                urls.setdefault(u,set()).add(os.path.relpath(p,root))
def check(u):
    try:
        r=subprocess.run(['curl','-sIL','--max-time','25','-o','/dev/null','-w','%{http_code} %{size_download} %{url_effective}',u],capture_output=True,text=True,timeout=40)
        return u, r.stdout.strip()
    except Exception as e:
        return u,'ERR '+str(e)
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as ex:
    for u,res in ex.map(check, sorted(urls)):
        print(f"{res.split()[0]:>8}  {u}\n            used in: {', '.join(sorted(urls[u]))}")

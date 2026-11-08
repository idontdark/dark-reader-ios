import urllib.request,urllib.parse,re,json,concurrent.futures
from pathlib import Path
def fetch(url):
 with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'}),timeout=20) as r:return r.geturl(),r.read().decode('utf-8')
def check(url):
 try:
  target,s=fetch(url)
  kv=s.split('<div class="bookkitem">')[1:]
  ak=s.split('<div class="content__main__articles--item')[1:]
  return {'url':url,'target':target,'knigavuheCards':len(kv),'aknigaCards':len(ak)}
 except Exception as e:return {'url':url,'error':str(e)}
urls=['https://knigavuhe.org/new/','https://knigavuhe.org/popular/','https://akniga.org/','https://akniga.org/index/top/']
with concurrent.futures.ThreadPoolExecutor(3) as pool:results=list(pool.map(check,urls))
for source,path in [('knigavuhe','https://knigavuhe.org/search/?q='),('akniga','https://akniga.org/search/books/?q=')]:
 count=0;titles=[]
 for page in range(1,4):
  _,html=fetch(path+urllib.parse.quote('Любовь')+'&page='+str(page))
  blocks=html.split('<div class="bookkitem">')[1:] if source=='knigavuhe' else html.split('<div class="content__main__articles--item')[1:]
  for block in blocks:
   pattern=r'<a[^>]*class="bookkitem_name"[^>]*>(.*?)</a>' if source=='knigavuhe' else r'<h2[^>]*>(.*?)</h2>'
   m=re.search(pattern,block,re.S|re.I)
   if m:titles.append(re.sub('<[^>]+>','',m[1]).strip());count+=1
 results.append({'source':source,'query':'Любовь','pages':3,'cards':count,'examples':titles[:3]})
Path('outputs/audio-source-tests/native-providers.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(results,ensure_ascii=False,indent=2))
for url in ['https://knigavuhe.org/genres/','https://akniga.org/sections/']:
 _,html=fetch(url)
 links=re.findall(r'<a[^>]+href="((?:https://akniga.org)?/(?:genre|section)/[^"?#]+)"[^>]*>(.*?)</a>',html,re.S)
 print(url,json.dumps({u:re.sub('<[^>]+>','',t).strip() for u,t in links if re.sub('<[^>]+>','',t).strip()},ensure_ascii=False))

import urllib.request,urllib.parse,json,re,concurrent.futures
from pathlib import Path
def get(url):
 with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'DarkReader/1.0 compatibility probe'}),timeout=25) as r:return r.read().decode('utf-8')
def probe(scope,word):
 q='mediatype:audio AND '+scope+' AND title:'+word+'*'
 u='https://archive.org/advancedsearch.php?'+urllib.parse.urlencode({'q':q,'rows':100,'output':'json','fl[]':['identifier','title','language']},doseq=True)
 try:
  d=json.loads(get(u))['response'];return {'scope':scope,'word':word,'total':d['numFound'],'returned':len(d['docs']),'examples':[x['title'] for x in d['docs'][:3]]}
 except Exception as e:return {'scope':scope,'word':word,'error':str(e)}
scopes=['collection:librivoxaudio','(collection:librivoxaudio OR collection:audio_bookspoetry OR subject:audiobooks OR subject:аудиокниги)']
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(lambda x:probe(*x),[(s,w) for s in scopes for w in ['любовь','love','любв']]))
Path('outputs/audio-source-tests/love-query.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(results,ensure_ascii=False,indent=2))
for name,url in [('akniga_search','https://akniga.org/search/books/?q='+urllib.parse.quote('Любовь')),('akniga_book','https://akniga.org/azimov-ayzek-nastoyaschaya-lyubov-1')]:
 try:
  s=get(url);Path('work/'+name+'.html').write_text(s,encoding='utf-8');print(name,'bytes',len(s));print('\n'.join(re.findall(r'.{0,100}(?:playlist|mp3|playerData|audio_url|player_json).{0,160}',s,re.I)[:10]))
 except Exception as e:print(name,str(e))

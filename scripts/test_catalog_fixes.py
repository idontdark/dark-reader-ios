import concurrent.futures,json,time,urllib.request,urllib.parse,datetime,re
from pathlib import Path
def get(url):
    with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'DarkReader/1.0 compatibility tests'}),timeout=30) as r:return json.load(r)
def book(lang,sort):
    year=datetime.date.today().year;code='rus' if lang=='ru' else 'eng'
    q='language:'+code+(f' first_publish_year:[{year-2} TO {year}]' if sort=='new' else '')
    url='https://openlibrary.org/search.json?'+urllib.parse.urlencode({'q':q,'lang':lang,'sort':sort,'limit':60,'fields':'key,first_publish_year,author_name,cover_i,editions,editions.key,editions.title,editions.language,editions.cover_i'})
    start=time.monotonic()
    try:
        data=get(url);cards=[]
        for d in data['docs']:
            ed=next((e for e in d.get('editions',{}).get('docs',[]) if not e.get('language') or code in e.get('language',[])),None)
            if not ed:continue
            if len(ed['title'])>300:continue
            if lang=='ru' and not re.search('[А-Яа-яЁё]',ed['title']):continue
            if sort=='new' and not year-2<=d.get('first_publish_year',0)<=year:continue
            cards.append({'title':ed['title'],'year':d.get('first_publish_year')})
        return {'test':'books_'+lang+'_'+sort,'seconds':round(time.monotonic()-start,2),'cards':len(cards),'examples':cards[:5],'url':url}
    except Exception as e:return {'test':'books_'+lang+'_'+sort,'error':str(e)}
def audio():
    meta=get('https://archive.org/metadata/dvoryanskoegnezdo_1906_librivox')
    tracks=[f for f in meta.get('files',[]) if f['name'].endswith('.mp3') and not f.get('private')]
    url='https://archive.org/download/dvoryanskoegnezdo_1906_librivox/'+urllib.parse.quote(tracks[0]['name'])
    with urllib.request.urlopen(urllib.request.Request(url,headers={'Range':'bytes=0-4095','User-Agent':'DarkReader/1.0'}),timeout=30) as r:
        sample=r.read(4096)
        return {'test':'romance_chapters_and_audio','chapters':len(tracks),'http':r.status,'contentType':r.headers.get('Content-Type'),'bytesRead':len(sample),'url':url}
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(lambda p:book(*p),[('ru','new'),('en','new'),('ru','readinglog')]))
try:results.append(audio())
except Exception as e:results.append({'test':'audio','error':str(e)})
Path('outputs/audio-source-tests/fixed-catalog-tests.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(results,ensure_ascii=False,indent=2))

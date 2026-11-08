import concurrent.futures,json,time,urllib.request,urllib.parse
from pathlib import Path
cases=[]
for name,params in [('latest',{'sort_order':'desc'}),('ru_title',{'title':'Война'}),('ru_author',{'author':'Толстой'}),('en_title',{'title':'Pride and Prejudice'}),('romance',{'genre':'romance'})]:
    cases.append(('librivox_'+name,'https://librivox.org/api/feed/audiobooks/?'+urllib.parse.urlencode({'format':'json','limit':30,'extended':1,**params})))
base='mediatype:audio AND (collection:librivoxaudio OR collection:audio_bookspoetry)'
for name,q,sort in [('popular_ru',base+' AND language:(rus OR ru OR Russian)','downloads desc'),('latest_ru',base+' AND language:(rus OR ru OR Russian)','publicdate desc'),('romance_ru',base+' AND language:(rus OR ru OR Russian) AND subject:(romance OR novel OR роман OR романы)','downloads desc'),('title_ru',base+' AND title:(война OR war)','downloads desc'),('author_ru',base+' AND creator:(толстой OR tolstoy)','downloads desc'),('en',base+' AND language:eng','downloads desc')]:
    cases.append(('archive_'+name,'https://archive.org/advancedsearch.php?'+urllib.parse.urlencode({'q':q,'fl[]':['identifier','title','language','downloads'],'rows':15,'sort[]':sort,'output':'json'},doseq=True)))
for name,words,lang in [('fixed_title_ru','title:дворянское* AND title:гнездо*','rus'),('fixed_author_ru','creator:tolstoy*','rus'),('fixed_title_en','title:pride* AND title:prejudice*','eng')]:
    cases.append((name,'https://archive.org/advancedsearch.php?'+urllib.parse.urlencode({'q':base+' AND ('+words+') AND language:'+lang,'fl[]':['identifier','title','language'],'rows':15,'output':'json'},doseq=True)))
def run(case):
    name,url=case;start=time.monotonic()
    try:
        with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'DarkReader/1.0 API compatibility test'}),timeout=35) as res:
            obj=json.load(res);rows=obj.get('books',obj.get('response',{}).get('docs',[]))
        return {'test':name,'seconds':round(time.monotonic()-start,2),'count':len(rows),'total':obj.get('response',{}).get('numFound'),'examples':[{'title':r.get('title'),'language':r.get('language'),'id':r.get('identifier',r.get('id'))} for r in rows[:3]],'url':url}
    except Exception as e:return {'test':name,'seconds':round(time.monotonic()-start,2),'error':str(e),'url':url}
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(run,cases))
Path('outputs/audio-source-tests').mkdir(parents=True,exist_ok=True)
Path('outputs/audio-source-tests/results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(results,ensure_ascii=False,indent=2))

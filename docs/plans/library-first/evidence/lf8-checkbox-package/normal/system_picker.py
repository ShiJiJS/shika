import business_ui as u
from ui_driver import tap

def choose(text,name):
 n=u.snap(name+'-before');items=[x for x in n if x.get('text')==text or x.get('content-desc')==text];assert len(items)==1,(text,len(items));tap(items[0],text);return u.snap(name+'-after')

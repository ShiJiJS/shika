import re
import business_ui as u,driver

def state(nodes,label,submit,value):
 c=[n for n in nodes if n.get('content-desc')==label and n.get('checkable')=='true'];assert len(c)==1 and c[0].get('checked')==str(value).lower(),(label,[n.attrib for n in c])
 b=[n for n in nodes if n.get('content-desc')==submit and n.get('class')=='android.widget.Button'];assert len(b)==1 and b[0].get('enabled')==str(value).lower(),(submit,[n.attrib for n in b])
 return c[0]

def box(nodes,label,name):
 c=[n for n in nodes if n.get('content-desc')==label and n.get('checkable')=='true'];assert len(c)==1
 x1,y1,x2,y2=map(int,re.findall(r'\d+',c[0].get('bounds')));assert x2-x1>180
 point=[x1+60,(y1+y2)//2]
 driver.record({'action':'tap-observed-checkbox-box','context':name,'point':point,'bounds':c[0].get('bounds'),'reference':'biz-0012-video-purge-open-after.png; leading box center60px from tile left at3physicalpx/dp'})
 driver.device('shell','input','tap',*map(str,point));return u.snap(name+'-after-box')

def exercise(label,submit,name,close='取消'):
 n=u.snap(name+'-initial');state(n,label,submit,False)
 n=u.choose(label,context=name+'-text-select');state(n,label,submit,True)
 n=box(n,label,name+'-box-clear');state(n,label,submit,False)
 n=box(n,label,name+'-box-select');state(n,label,submit,True)
 u.choose(close,context=name+'-cancel')
 u.check(name,{'text_select_box_clear_and_select':True,'submit_enabled_only_checked':True,'closed_while_checked_without_submit':True})

def check_reopen(label,submit,name,close='取消'):
 n=u.snap(name+'-reopen');state(n,label,submit,False);u.choose(close,context=name+'-reopen-cancel');u.check(name+'-draft-reset',{'reopened_unchecked':True,'submit_disabled':True})

import business_ui as u,driver,snapshot_all
label='选择回收内容 flower-landscape'
def checked(n,value):
 a=[x for x in n if x.get('content-desc')==label];assert len(a)==1 and a[0].get('checked')==str(value).lower()
n=u.choose(label,context='trash-box-selected');checked(n,True);u.expect_text(n,'已选 1')
n=u.choose(prefix='flower-landscape\n',context='trash-row-text-deselected');checked(n,False);u.expect_text(n,'已选 0')
n=u.choose(label,context='trash-box-reselected');checked(n,True);u.expect_text(n,'已选 1');u.check('trash-row-box-and-text-single-toggle',{'selected_count':1,'no_file_command':True})
u.choose('永久删除',context='video-purge-open')

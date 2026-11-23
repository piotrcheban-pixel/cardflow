import sys, numpy as np
sys.path.insert(0,'review_visual/tools')
from PIL import Image
import v7_measure2 as m
p='review_visual/screenshots/v7_after/live_01_classic_question_2560x1410.png'
img=Image.open(p).convert('RGB')
rect=m.find_card(img)
print('rect',rect)
arr=np.array(img).astype(int)
x0,y0,x1,y1=rect
inner=arr[y0+5:y1-4,x0+5:x1-4]
diff=np.abs(inner-np.array([255,255,255])).max(axis=2)
content=diff>26
ys,xs=np.nonzero(content)
print('content bbox',xs.min(),ys.min(),xs.max(),ys.max())
for y in (ys.min(), ys.min()+3, ys.max()-3, ys.max()):
    row=np.nonzero(content[y])[0]
    print('row',y,'count',len(row),'first',row[:6],'last',row[-6:])
print('corner px',inner[0,0],inner[0,-1],inner[-1,0],inner[-1,-1])
print('mid px',arr[(y0+y1)//2, x0+8], arr[y0+8,(x0+x1)//2])

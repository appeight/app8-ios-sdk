import json
E=[{"type":"top","target":"superview"},{"type":"leading","target":"superview"},{"type":"trailing","target":"superview"},{"type":"bottom","target":"superview"}]
def fill(c): return [{"id":"f"+c.strip('#'),"type":"fill","content":{"solid":c}}]
products=[{"id":f"p{i}","title":f"ITEM {i}","price":f"{i*10+9} EUR","img":f"photo-{i}",
           "images":[{"name":f"photo-{i}"},{"name":f"photo-{i}b"},{"name":f"photo-{i}c"}]} for i in range(1,7)]
push_zoom=lambda src,align:{"type":"navigation","nextScreen":"product","presentation":"push","params":{"product":"{{item}}"},
    "transition":{"preset":"zoom","sourceKey":src,"alignmentKey":align}}
ShowPage={"id":"ShowPage","type":"view","content":{"style":{"material":fill("#000000")},"children":[
  {"id":"pagePhoto","type":"image","content":{"properties":{"type":"remoteAsset","name":"{{item.img}}"},"style":{"contentMode":"scaleAspectFill"},
    "layout":{"constraints":E},"interaction":{"clipsToBounds":"true"},"transition":{"key":"{{'show-' + item.id}}"}}},
  {"id":"pageText","type":"label","content":{"properties":{"text":"{{item.title}}","numberOfLines":1},"style":{"text":{"fontSize":28,"fontWeight":"bold","color":"#FFFFFF"}},
    "layout":{"constraints":[{"type":"leading","target":"superview","constant":16},{"type":"bottom","target":"superview","constant":-120}]}}},
  {"id":"pageButton","type":"button","content":{"properties":{"text":""},"style":{"system":{"variant":"plain"}},"layout":{"constraints":E},
    "accessibility":{"label":"{{'open ' + item.id}}"},
    "actions":{"tap":[push_zoom("{{'show-' + item.id}}","gallery-0")]}}}]}}
Card={"id":"Card","type":"view","content":{"children":[
  {"id":"cardBox","type":"view","content":{"layout":{"constraints":[{"type":"top","target":"superview"},{"type":"leading","target":"superview"},{"type":"trailing","target":"superview"},
     {"type":"height","target":"superview","attribute":"width","multiplier":1.25}]},"children":[
     {"id":"cardImage","type":"image","content":{"properties":{"type":"remoteAsset","name":"{{item.img}}"},"style":{"contentMode":"scaleAspectFill"},
       "layout":{"constraints":E},"interaction":{"clipsToBounds":"true"},"transition":{"key":"{{'card-' + item.id}}"}}}]}},
  {"id":"cardTitle","type":"label","content":{"properties":{"text":"{{item.title}}","numberOfLines":1},"style":{"text":{"fontSize":12}},
    "layout":{"constraints":[{"type":"top","target":"cardBox","attribute":"bottom","constant":8},{"type":"leading","target":"superview","constant":8},{"type":"bottom","target":"superview","constant":-8}]}}}],
  "accessibility":{"label":"{{'card ' + item.id}}"},
  "contextMenu":{"preview":{"component":{"templateId":"QuickView"},"width":300,"cornerRadius":0},
    "items":[{"id":"save","title":"Save","icon":"star","actions":[{"type":"toggleArrayValue","variableName":"saved","value":"{{item.id}}"}]},
             {"id":"view","title":"View product","icon":"arrow.up.right","actions":[push_zoom("{{'card-' + item.id}}","fit-0")]}],
    "onPreviewTap":[push_zoom("{{'card-' + item.id}}","fit-0")]}}}
QuickView={"id":"QuickView","type":"view","content":{"style":{"material":fill("#FFFFFF")},"children":[
  {"id":"qvImage","type":"image","content":{"properties":{"type":"remoteAsset","name":"{{item.img}}"},"style":{"contentMode":"scaleAspectFill"},
    "layout":{"constraints":[{"type":"top","target":"superview"},{"type":"leading","target":"superview"},{"type":"trailing","target":"superview"},{"type":"height","target":"superview","attribute":"width","multiplier":1.25}]},"interaction":{"clipsToBounds":"true"}}},
  {"id":"qvText","type":"stackView","content":{"properties":{"axis":"vertical","spacing":6,"alignment":"fill"},
    "layout":{"constraints":[{"type":"top","target":"qvImage","attribute":"bottom","constant":12},{"type":"leading","target":"superview","constant":16},{"type":"trailing","target":"superview","constant":-16},{"type":"bottom","target":"superview","constant":-16}]},
    "children":[{"id":"qvTitle","type":"label","content":{"properties":{"text":"{{item.title}}"},"style":{"text":{"fontSize":13,"fontWeight":"semibold"}}}},
                {"id":"qvPrice","type":"label","content":{"properties":{"text":"{{item.price}}"},"style":{"text":{"fontSize":13}}}}]}}]}}
home={"type":"screen","id":"home","content":{"navigationBar":{"hidden":True},"style":{"material":fill("#000000")},"variables":{"homePage":{"type":"number","initialValue":0}},
  "children":[{"id":"showroom","type":"collection","content":{"properties":{"data":"{{products}}","templateName":"ShowPage",
     "layout":{"type":"vertical","pagingStyle":"paging","itemHeight":"fill","currentPageVariable":"homePage","showsScrollIndicator":False}},"layout":{"constraints":E}}}]}}
gallery_cell={"id":"galleryCell","type":"view","content":{"style":{"material":fill("#EEEEEE")},"children":[
  {"id":"galleryImg","type":"image","content":{"properties":{"type":"remoteAsset","name":"{{item.name}}"},"style":{"contentMode":"scaleAspectFill"},
    "layout":{"constraints":E},"interaction":{"clipsToBounds":"true"},"transition":{"key":"{{'gallery-' + item.$index}}"}}},
  {"id":"galleryFit","type":"view","content":{"layout":{"constraints":[{"type":"leading","target":"superview"},{"type":"trailing","target":"superview"},{"type":"centerY","target":"superview"},
     {"type":"height","target":"superview","attribute":"width","multiplier":1.25}]},"interaction":{"enabled":"false"},"transition":{"key":"{{'fit-' + item.$index}}"}}}]}}
def spacer(i,h): return {"id":f"sp{i}","type":"view","content":{"layout":{"height":h}}}
def text(i,t,size=14): return {"id":f"tx{i}","type":"view","content":{"children":[{"id":f"txl{i}","type":"label","content":{"properties":{"text":t,"numberOfLines":0},"style":{"text":{"fontSize":size}},
   "layout":{"constraints":[{"type":"top","target":"superview"},{"type":"leading","target":"superview","constant":16},{"type":"trailing","target":"superview","constant":-16},{"type":"bottom","target":"superview"}]}}}]}}
body=[{"id":"galleryBox","type":"view","content":{"layout":{"constraints":[{"type":"height","target":"superview","attribute":"width","multiplier":1.5}]},"children":[
   {"id":"gallery","type":"collection","content":{"properties":{"data":"{{product.images}}","layout":{"type":"horizontal","pagingStyle":"paging","itemHeight":"fill","currentPageVariable":"galleryPage","showsScrollIndicator":False}},
     "layout":{"constraints":E},"template":gallery_cell}}]}},
  spacer(1,24), text(1,"{{product.title}}",20), spacer(2,8), text(2,"{{product.price}}")]
for i in range(3,9):
    body += [spacer(i*10,24), text(i,"Section text that runs over a few lines so the screen scrolls and the last line can be checked against the bottom bar. "*3)]
body += [text(99,"LAST LINE"), spacer(100,24)]
product={"type":"screen","id":"product","content":{"hidesTabBar":True,
  "navigationBar":{"tintColor":"#000000","backLabel":"","rightActions":[{"icon":"{{includes(saved, product.id) ? 'star.fill' : 'star'}}","action":[{"type":"toggleArrayValue","variableName":"saved","value":"{{product.id}}"}]}]},
  "style":{"material":fill("#FFFFFF")},"variables":{"galleryPage":{"type":"number","initialValue":0}},
  "bottomBar":{"component":{"id":"buyBar","type":"view","content":{"style":{"material":fill("#000000")},"layout":{"height":50},"children":[
     {"id":"buyLabel","type":"label","content":{"properties":{"text":"ADD TO BAG","numberOfLines":1},"style":{"text":{"fontSize":13,"color":"#FFFFFF"}},"layout":{"constraints":[{"type":"centerX","target":"superview"},{"type":"centerY","target":"superview"}]}}}]}},
     "insets":{"top":8,"left":16,"bottom":8,"right":16}},
  "children":[{"id":"pdpScroll","type":"scrollView","content":{"properties":{"direction":"vertical","showsIndicator":False,"contentInsetAdjustment":"never","stretchesTopChild":True},
     "layout":{"constraints":E},"children":[{"id":"pdpStack","type":"stackView","content":{"properties":{"axis":"vertical","spacing":0,"alignment":"fill"},"layout":{"constraints":E},"children":body}}]}}]}}
saved={"type":"screen","id":"saved","content":{"navigationBar":{"title":"Saved","tintColor":"#000000"},"style":{"material":fill("#FFFFFF")},
  "children":[{"id":"savedScroll","type":"scrollView","content":{"properties":{"direction":"vertical"},"layout":{"constraints":E},"children":[
    {"id":"grid","type":"collection","content":{"properties":{"data":"{{products}}","templateName":"Card","layout":{"type":"grid","columns":2,"itemSpacing":2,"lineSpacing":16,"scrollEnabled":False,"estimatedItemHeight":300}},
      "layout":{"constraints":E},"actions":{"onItemTap":[push_zoom("{{'card-' + item.id}}","fit-0")]}}}]}}]}}
bag={"type":"screen","id":"bag","content":{"navigationBar":{"title":"Bag"},"style":{"material":fill("#FFFFFF")},"children":[
  {"id":"openGrid","type":"button","content":{"properties":{"text":"OPEN GRID"},"style":{"system":{"variant":"filled"}},
    "layout":{"constraints":[{"type":"centerX","target":"superview"},{"type":"centerY","target":"superview"}]},
    "actions":{"tap":[{"type":"navigation","nextScreen":"category","presentation":"push"}]}}},
  {"id":"openInfo","type":"button","content":{"properties":{"text":"OPEN INFO"},"style":{"system":{"variant":"filled"}},
    "layout":{"constraints":[{"type":"centerX","target":"superview"},{"type":"top","target":"openGrid","attribute":"bottom","constant":24}]},
    "actions":{"tap":[{"type":"navigation","nextScreen":"info","presentation":"push"}]}}}]}}
info={"type":"screen","id":"info","content":{"navigationBar":{"title":"Info"},"style":{"material":fill("#FFFFFF")},"children":[
  {"id":"infoText","type":"label","content":{"properties":{"text":"Plain screen"},"layout":{"constraints":[{"type":"centerX","target":"superview"},{"type":"centerY","target":"superview"}]}}}]}}
# A category grid pushed with a plain push: the system content back swipe must work on it.
category={"type":"screen","id":"category","content":{"navigationBar":{"title":"Category","tintColor":"#000000","backLabel":""},"style":{"material":fill("#FFFFFF")},
  "children":[{"id":"catGrid","type":"collection","content":{"properties":{"data":"{{products}}","templateName":"Card","layout":{"type":"grid","columns":2,"itemSpacing":2,"lineSpacing":16,"estimatedItemHeight":300}},
    "layout":{"constraints":E}}}]}}
# A tab root with a coloured cover under the status bar (contentInsetAdjustment bottom),
# the cover's height from `height >= width`, a decorative image and a text block pinned to
# the safe area, and a block pinned to the cover's bottom: the stretchy top's cover case.
def label(i,t,size,color="#FFFFFF",weight="regular"): return {"id":i,"type":"label","content":{"properties":{"text":t,"numberOfLines":1},"style":{"text":{"fontSize":size,"fontWeight":weight,"color":color}}}}
coverHero={"id":"coverHero","type":"view","content":{"style":{"material":fill("#B0202A")},
  "layout":{"constraints":[{"type":"height","target":"superview","attribute":"width","op":">=","multiplier":1}]},"children":[
  {"id":"coverMark","type":"view","content":{"layout":{"constraints":[{"type":"trailing","target":"superview","constant":150},{"type":"top","target":"safeArea","constant":40},
     {"type":"width","target":"superview","multiplier":0.95},{"type":"height","target":"superview","attribute":"width","multiplier":0.36}]},"children":[
     {"id":"coverMarkImg","type":"image","content":{"properties":{"type":"remoteAsset","name":"cover-mark"},"style":{"contentMode":"scaleAspectFit","alpha":0.25},"layout":{"constraints":E}}}]}},
  {"id":"coverText","type":"stackView","content":{"properties":{"axis":"vertical","spacing":6,"alignment":"fill"},
     "layout":{"constraints":[{"type":"leading","target":"superview","constant":16},{"type":"trailing","target":"superview","constant":-16},{"type":"top","target":"safeArea","constant":76},{"type":"bottom","target":"superview","constant":-24}]},
     "children":[label("coverKicker","FRIDAY 20:00",13),label("coverTitle","HOME TEAM",40,weight="heavy"),label("coverVs","v",16),label("coverTitle2","AWAY TEAM",40,weight="heavy"),
       {"id":"coverGap","type":"view","content":{"layout":{"height":16}}},
       {"id":"coverButtons","type":"stackView","content":{"properties":{"axis":"horizontal","spacing":8,"distribution":"fillEqually"},"children":[
         {"id":"coverBtn1","type":"button","content":{"properties":{"text":"Primary"},"style":{"system":{"variant":"filled","baseBackgroundColor":"#FFFFFF","baseForegroundColor":"#B0202A","cornerStyle":"capsule"}},"layout":{"height":44}}},
         {"id":"coverBtn2","type":"button","content":{"properties":{"text":"Secondary"},"style":{"system":{"variant":"bordered","baseForegroundColor":"#FFFFFF","cornerStyle":"capsule"}},"layout":{"height":44}}}]}}]}}]}}
coverBody=[coverHero]
for i in range(1,8):
    coverBody += [spacer(200+i,24), text(200+i,"Section text that runs over a few lines so the screen scrolls well past the cover. "*3)]
cover={"type":"screen","id":"cover","content":{"navigationBar":{"tintColor":"#000000","topEdgeEffect":"hidden","rightActions":[{"icon":"person.crop.circle","action":[{"type":"dismiss"}]}]},
  "style":{"material":fill("#FFFFFF")},
  "children":[{"id":"coverScroll","type":"scrollView","content":{"properties":{"direction":"vertical","showsIndicator":False,"contentInsetAdjustment":"bottom","stretchesTopChild":True},
     "layout":{"constraints":E},"children":[{"id":"coverStack","type":"stackView","content":{"properties":{"axis":"vertical","spacing":0,"alignment":"fill"},"layout":{"constraints":E},"children":coverBody}}]}}]}}
tabs={"type":"tabBarScreen","id":"tabs","content":{"tabs":[{"id":"home","label":"HOME","icon":"house","screen":"home"},
   {"id":"saved","label":"SAVED","icon":"star","screen":"saved","badge":"{{length(saved) > 0 ? length(saved) : ''}}"},
   {"id":"bag","label":"BAG","icon":"bag","screen":"bag","badge":"12"},
   {"id":"cover","label":"COVER","icon":"square","screen":"cover"}],"initialTab":"home",
   "tintColor":"#FFFFFF","unselectedColor":"#FFFFFF4D","badgeColor":"#FFFFFF","badgeTextColor":"#000000",
   "barStyle":{"variant":"text","shape":"floating","background":"#000000","cornerRadius":0,"height":32,"selection":"opacity","unselectedOpacity":0.3,
     "text":{"fontSize":12,"fontWeight":"semibold","color":"#FFFFFF"},"badgePlacement":"inline"}}}
app={"title":"Harness","navigation":{"startFlow":"main","flows":[{"id":"main","startScreen":"tabs"}]},
  "variables":{"products":{"type":"array","initialValue":products},"saved":{"type":"array","initialValue":["p1","p2"]}}}
bundle={"app":app,"styles":[],"components":[ShowPage,Card,QuickView],"screens":{"tabs":tabs,"home":home,"product":product,"saved":saved,"bag":bag,"category":category,"info":info,"cover":cover}}
json.dump(bundle,open("App/fixture.json","w"),indent=1)

#!/usr/bin/env python3
"""Regenerate the checked-in architecture PNG/SVG images (requires Pillow)."""
from pathlib import Path
from html import escape
from math import atan2, cos, sin, pi
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent / 'images'
ROOT.mkdir(exist_ok=True)
FONT = '/System/Library/Fonts/Supplemental/Arial.ttf'
BOLD = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
# Set these to your platform's TrueType font paths if regenerating off macOS.
SCALE = 1.5

class Diagram:
    def __init__(self, name, title, subtitle, width=1440, height=1040):
        self.name, self.width, self.height = name, width, height
        self.image = Image.new('RGB', (int(width * SCALE), int(height * SCALE)), '#f5f7fb')
        self.draw = ImageDraw.Draw(self.image)
        self.svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">',
                    f'<title id="title">{escape(title)}</title><desc id="desc">{escape(subtitle)}</desc>',
                    f'<rect width="{width}" height="{height}" fill="#f5f7fb"/>']
        self.text(width / 2, 46, title, 32, True)
        self.text(width / 2, 84, subtitle, 19, color='#526278')

    def text(self, x, y, value, size=20, bold=False, color='#17263c'):
        font = ImageFont.truetype(BOLD if bold else FONT, int(size * SCALE))
        self.draw.text((x * SCALE, y * SCALE), value, font=font, fill=color, anchor='mm')
        self.svg.append(f'<text x="{x}" y="{y}" text-anchor="middle" dominant-baseline="central" font-family="Arial, sans-serif" font-size="{size}" font-weight="{700 if bold else 400}" fill="{color}">{escape(value)}</text>')

    def box(self, x, y, w, h, title, lines=(), fill='#e7efff', stroke='#9db6e0'):
        self.draw.rounded_rectangle((x*SCALE,y*SCALE,(x+w)*SCALE,(y+h)*SCALE), radius=12*SCALE, fill=fill, outline=stroke, width=2)
        self.svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{fill}" stroke="{stroke}"/>')
        total = 28 + len(lines) * 25
        start = y + (h-total)/2 + 14
        self.text(x+w/2, start, title, 21, True)
        for n, line in enumerate(lines):
            self.text(x+w/2, start+29+n*25, line, 17, color='#384a62')

    def arrow(self, points, label=None, color='#697d99'):
        scaled=[(x*SCALE,y*SCALE) for x,y in points]
        self.draw.line(scaled, fill=color, width=3)
        x,y=points[-1]; px,py=points[-2]
        angle=atan2(y-py,x-px)
        triangle=[(x,y),(x-11*cos(angle-pi/6),y-11*sin(angle-pi/6)),(x-11*cos(angle+pi/6),y-11*sin(angle+pi/6))]
        self.draw.polygon([(a*SCALE,b*SCALE) for a,b in triangle],fill=color)
        self.svg.append(f'<polyline points="{" ".join(f"{a},{b}" for a,b in points)}" fill="none" stroke="{color}" stroke-width="2"/>')
        self.svg.append(f'<polygon points="{" ".join(f"{a},{b}" for a,b in triangle)}" fill="{color}"/>')
        if label:
            lx,ly,text=label
            self.text(lx,ly,text,16,color=color)

    def save(self):
        self.image.save(ROOT/f'{self.name}.png', optimize=True)
        (ROOT/f'{self.name}.svg').write_text('\n'.join(self.svg+['</svg>'])+'\n')


d = Diagram('architecture','Glimpse: major components','Arrows show ownership or calls; UI stays on the main actor, services own their state.',height=1100)
d.box(530,120,380,90,'AppDelegate',['Application lifetime + viewer collection'])
d.arrow([(600,210),(280,250)])
d.arrow([(840,210),(1060,250)])
d.box(90,250,380,90,'AppMenuController',['Top-level menus + change callbacks'])
d.box(870,250,380,90,'ViewerWindowController',['Native window, toolbar + inspector'])
d.arrow([(280,340),(280,380)])
d.arrow([(1060,340),(1060,380)])
d.box(90,380,380,110,'Feature UI controllers',['Background menu + RGB editor','Actions menu + ActionRunner'])
d.box(870,380,380,110,'ImageViewController',['Navigation, zoom + presentation','Native image / scroll / clip views'])
d.text(720,553,'GlimpseCore services',23,True,color='#24624e')
for points in [[(220,490),(165,600)],[(350,490),(495,600)],[(1060,490),(825,600)],[(1250,295),(1360,295),(1360,570),(1155,600)]]:
    d.arrow(points)
core=dict(fill='#e5f4ee',stroke='#95c5b1')
d.box(30,600,270,125,'Preferences + Layout',['Zoom / background stores','Pure ImageSizing rules'],**core)
d.box(360,600,270,125,'Actions configuration',['JSON validation + tokens','Serialized config I/O'],**core)
d.box(690,600,270,125,'ImageRepository actor',['Navigation + bounded LRU','Foreground / prefetch routing'],**core)
d.box(1020,600,270,125,'Metadata reader actor',['ImageIO + container fields','Feeds metadata inspector'],**core)
d.arrow([(825,725),(825,780)])
d.box(690,780,270,100,'Decode worker actors',['ImageDecoder + ImageIO','Separate foreground / prefetch'],**core)
d.arrow([(495,725),(495,935)])
d.arrow([(825,880),(825,915),(620,915),(620,935)])
d.arrow([(1155,725),(1155,980),(660,980)])
d.box(330,935,330,90,'BoundedLocalFileReader',['One validated regular-file read'],fill='#edf0f5',stroke='#b0bac8')
d.text(720,1061,'AppKit execution stays in the app. Core configuration never launches a command.',18,color='#526278')
d.save()


d = Diagram('repository-map','Glimpse: repository and build layout','The app and unit tests compile the same GlimpseCore sources; no duplicated implementation.',height=880)
d.box(70,140,420,115,'Glimpse / Sources',['App · Viewer · Appearance','Actions · Metadata'])
d.box(540,140,370,115,'GlimpseCore / Sources',['Preferences · Layout · Navigation','Files · Imaging · Actions · Metadata'],fill='#e5f4ee',stroke='#95c5b1')
d.box(970,140,400,115,'Tests / GlimpseCoreTests',['Behavior and regression coverage','Generated image fixtures'],fill='#fff2da',stroke='#dbc394')
d.arrow([(280,255),(280,340)])
d.arrow([(660,255),(660,300),(400,300),(400,340)])
d.arrow([(800,255),(800,340)])
d.arrow([(1170,255),(1170,300),(1000,300),(1000,340)])
d.box(160,340,410,105,'Glimpse.xcodeproj',['App + static core framework targets','Produces Glimpse.app'])
d.box(740,340,410,105,'Package.swift',['Core library + unit test targets','Runs core tests'],fill='#fff2da',stroke='#dbc394')
d.arrow([(365,445),(365,525)])
d.arrow([(945,445),(945,490),(600,490),(600,525)])
d.box(160,525,650,100,'scripts / + .github / workflows',['Build/test checks · secret scanning · optional CodeQL','Universal signing and notarization packaging'])
d.box(900,525,420,100,'Resources and declarations',['Asset catalog · Info.plist','Entitlements · LICENSE'],fill='#edf0f5',stroke='#b0bac8')
d.box(160,690,1160,95,'Documentation',['README: usage  |  specs/: current design + diagrams  |  docs/: configuration, distribution, audit'],fill='#edf0f5',stroke='#b0bac8')
d.text(720,838,'Build products are ignored. Documentation render tools are not app dependencies.',18,color='#526278')
d.save()


d = Diagram('image-pipeline','Glimpse: image loading and prefetch','Foreground work and speculative decoding have separate workers; only the current request updates the UI.',height=1120)
d.box(60,145,360,90,'Open / arrow-key navigation',['Local URL + current request ID'])
d.arrow([(420,190),(520,190)])
d.box(520,145,360,90,'ImageRepository actor',['Normalize URL · fingerprint file'])
d.arrow([(700,235),(700,305)])
d.box(520,305,360,90,'Valid cache or pending load?',['LRU hit / matching prefetch'])
d.arrow([(520,350),(240,350),(240,505)],(330,325,'hit'))
d.arrow([(880,350),(1160,350),(1160,465)],(1035,325,'miss'))
d.box(60,505,360,100,'Return image result',['Controller checks cancellation','and request ID before display'])
d.box(980,465,360,115,'Foreground worker',['Bounded file read + limits','ImageIO decode / EXIF transform'],fill='#e5f4ee',stroke='#95c5b1')
d.arrow([(1160,580),(1160,660)])
d.box(980,660,360,90,'Recheck + cache',['File unchanged? Store if eligible'],fill='#e5f4ee',stroke='#95c5b1')
d.arrow([(980,705),(700,705),(700,555),(420,555)])
d.arrow([(240,605),(240,780)])
d.box(60,780,360,110,'Main-actor presentation',['Apply zoom + title + background','Failures clear old content'])
d.arrow([(420,835),(545,835)])
d.box(545,780,350,110,'Suggest adjacent images',['Direction-aware next / previous','At most two unique neighbors'])
d.arrow([(895,835),(980,835),(980,935)])
d.box(800,935,540,110,'Separate speculative worker',['Decode eligible neighbors; skip GIF/TIFF','Validate version before bounded cache insertion'],fill='#e5f4ee',stroke='#95c5b1')
d.text(390,1010,'Per-window LRU: 3 images / 256 MB estimate',19,True,color='#24624e')
d.text(390,1040,'Mutable animation representations are not cached.',17,color='#526278')
d.text(720,1090,'Cancellation prevents stale display; native codec calls cannot be interrupted mid-operation.',18,color='#526278')
d.save()
print('Rendered PNG + SVG:', ', '.join(p.name for p in sorted(ROOT.iterdir())))

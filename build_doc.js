const fs = require("fs");
const { Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  AlignmentType, LevelFormat, HeadingLevel, BorderStyle, WidthType, ShadingType,
  ExternalHyperlink, PageBreak, TableOfContents } = require("docx");

const FONT = "Arial";
const NAVY = "1F3864", BLUE = "2E75B6", GREY = "595959";
const b = (style) => ({ style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" });
const cellB = { top:b(),bottom:b(),left:b(),right:b() };
const M = { top:80, bottom:80, left:120, right:120 };

function P(text, opts={}) {
  return new Paragraph({ spacing:{after:120}, ...opts,
    children: Array.isArray(text)?text:[new TextRun({ text, font:FONT, size:22, ...(opts.run||{}) })] });
}
function H1(t){ return new Paragraph({ heading:HeadingLevel.HEADING_1, children:[new TextRun({text:t,font:FONT})] }); }
function H2(t){ return new Paragraph({ heading:HeadingLevel.HEADING_2, children:[new TextRun({text:t,font:FONT})] }); }
function H3(t){ return new Paragraph({ heading:HeadingLevel.HEADING_3, children:[new TextRun({text:t,font:FONT})] }); }
function bullet(t){ return new Paragraph({ numbering:{reference:"bul",level:0}, spacing:{after:60},
  children:[new TextRun({text:t,font:FONT,size:22})] }); }

function cell(text, {w, fill, bold=false, color, align}={}) {
  const runs = Array.isArray(text) ? text :
    [new TextRun({ text, font:FONT, size:20, bold, color })];
  return new TableCell({ borders:cellB, margins:M,
    width:{size:w,type:WidthType.DXA},
    shading: fill?{fill,type:ShadingType.CLEAR}:undefined,
    children:[new Paragraph({ alignment:align||AlignmentType.LEFT, children:runs })] });
}
function hcell(t,w){ return cell(t,{w,fill:NAVY,bold:true,color:"FFFFFF",align:AlignmentType.CENTER}); }

function table(widths, headerCells, dataRows, shadeAlt=true) {
  const rows = [ new TableRow({ tableHeader:true, children:headerCells }) ];
  dataRows.forEach((r,i)=>{
    rows.push(new TableRow({ children: r.map((c,j)=>{
      if (typeof c === "object" && c.cell) return c.cell;
      return cell(c,{w:widths[j], fill: shadeAlt && i%2===1 ? "EAF0F8":undefined, bold:j===0&&c.length<30});
    })}));
  });
  return new Table({ width:{size:widths.reduce((a,x)=>a+x,0),type:WidthType.DXA}, columnWidths:widths, rows });
}

// SWOT 2x2
function swot(s,w,o,t){
  const W=4680;
  const box = (title, items, fill) => cell(
    [ new TextRun({text:title,font:FONT,size:20,bold:true,color:"FFFFFF"}),
      ...items.flatMap(it=>[new TextRun({text:"\n• "+it,font:FONT,size:18,color:"FFFFFF",break:0})]) ],
    {w:W, fill});
  // build with line breaks
  const mk = (title, items, fill) => {
    const kids=[new Paragraph({children:[new TextRun({text:title,font:FONT,size:20,bold:true,color:"FFFFFF"})]})];
    items.forEach(it=>kids.push(new Paragraph({spacing:{before:20},children:[new TextRun({text:"• "+it,font:FONT,size:18,color:"FFFFFF"})]})));
    return new TableCell({borders:cellB,margins:M,width:{size:W,type:WidthType.DXA},shading:{fill,type:ShadingType.CLEAR},children:kids});
  };
  return new Table({width:{size:9360,type:WidthType.DXA},columnWidths:[W,W],rows:[
    new TableRow({children:[mk("Strengths",s,"2E7D32"),mk("Weaknesses",w,"C62828")]}),
    new TableRow({children:[mk("Opportunities",o,"1565C0"),mk("Threats",t,"E65100")]}),
  ]});
}

const children = [];

// Title
children.push(new Paragraph({ alignment:AlignmentType.LEFT, spacing:{after:60},
  children:[new TextRun({text:"Trip & Events App Portfolio",font:FONT,size:44,bold:true,color:NAVY})] }));
children.push(new Paragraph({ spacing:{after:40},
  children:[new TextRun({text:"A ship-cash-learn roadmap: six standalone products, prioritized",font:FONT,size:26,color:BLUE})] }));
children.push(new Paragraph({ spacing:{after:240},
  children:[new TextRun({text:"Prepared for Tiziano · May 2026 · Frameworks: Weighted Scorecard, RICE, SWOT, Competitor Analysis",font:FONT,size:18,italics:true,color:GREY})] }));

children.push(H1("1. The approach"));
children.push(P("You don’t want to build the whole vision in the dark. So this plan splits the travel-memory idea into six products that can each ship on their own, earn on their own, and give you a real read on demand before you commit more capital. Each product is also a deliberate stepping stone toward the integrated endgame — you release, cash, learn, and only then build the next, more expensive layer."));
children.push(P("Two prioritization lenses are used so the ranking isn’t a single opinion. A weighted scorecard tuned to your stated priorities (time-to-cash and strategic fit weighted highest, then market size) and RICE (Reach × Impact × Confidence ÷ Effort), the standard product-prioritization formula. Where they disagree, that disagreement is itself a signal — explained in Section 7."));

children.push(H1("2. Portfolio at a glance"));
children.push(P("Both frameworks independently rank SplitTrip first by a wide margin. The middle three (EventList, TripBoard, TripReel) cluster close together; TripMap ranks last in both because it is the most expensive to build and the hardest to monetize alone."));
children.push(table(
  [620,1500,1900,1450,1300,1290,1300],
  [hcell("Rank",620),hcell("Product",1500),hcell("Segment",1900),hcell("Weighted /100",1450),hcell("RICE",1300),hcell("Build effort",1290),hcell("Wave",1300)],
  [
   ["1","SplitTrip","Group finance","90.0","8.53","Low","1"],
   ["2","TripBoard","Travel planning","72.5","1.20","Medium","2b"],
   ["3","EventList","Events / social","71.7","2.80","Low","2"],
   ["3","TripReel","Memories / media","71.7","1.50","High","4"],
   ["5","The Suite","Integrated platform","68.3","1.07","Very high","5"],
   ["6","TripMap","Location / GIS","53.3","0.30","High","3"],
  ]));
children.push(P("“Wave” is the recommended ship order (Section 7), which is not identical to raw score — it also respects dependencies (TripMap must exist before TripReel can pull route data, even though TripReel scores higher).", {run:{italics:true,size:18,color:GREY}}));

children.push(new Paragraph({children:[new PageBreak()]}));
children.push(H1("3. The six products"));

// Helper to render a product block
function product(num, name, seg, oneliner, mvpIn, mvpOut, monet, swotData, comp){
  children.push(H2(`${num}. ${name} — ${seg}`));
  children.push(P([new TextRun({text:oneliner,font:FONT,size:22,italics:true,color:NAVY})]));
  children.push(H3("MVP scope (in)"));
  mvpIn.forEach(x=>children.push(bullet(x)));
  children.push(H3("Explicitly out of scope (v1)"));
  mvpOut.forEach(x=>children.push(bullet(x)));
  children.push(H3("Monetization"));
  children.push(P(monet));
  children.push(H3("SWOT"));
  children.push(swot(swotData.s,swotData.w,swotData.o,swotData.t));
  children.push(P(""));
  children.push(H3("Competitive read"));
  children.push(P(comp));
  children.push(P(""));
}

product("3.1","SplitTrip","Group finance (Wave 1 — the wedge)",
 "Bill-splitting, but framed around a trip or event with a start, an end, and a guest list — not an open-ended ledger.",
 ["Create a trip/event; invite friends by shareable link (no account needed to join)",
  "Add expenses, assign who-owes-what, multi-currency entry, running balances",
  "“Settle up” summary and payment hand-off (link to Venmo/PayPal/bank, not in-app payments v1)",
  "Simple per-trip guest list (seeds EventList and the broader social graph)"],
 ["In-app payment processing / wallet (regulatory + cost burden)",
  "Receipt OCR (ship as the first paid upgrade, not in free v1)",
  "Itinerary, location, media — all later waves"],
 "Freemium. Free core drives the invite-to-split viral loop; charge $3–5/mo (or per-trip) for receipt scanning, automatic currency conversion, unlimited trips, and ad-free — the exact wall Splitwise uses, which proves the willingness to pay. Target 3–5% free→paid.",
 {s:["Trivial to build (CRUD + arithmetic)","Built-in virality: every bill drags in 3–6 friends","Recurring, real pain people already pay to solve"],
  w:["Crowded category; hard to dethrone Splitwise","Low ARPU in this space","“Trip framing” alone is thin differentiation"],
  o:["Splitwise gates free at 3 expenses/day — a generous free tier wins switchers","Own the trip context Splitwise lacks, then expand into memories"],
  t:["Splitwise/Wanderlog could copy trip framing cheaply","Venmo/PayPal group features encroach"]},
 "Splitwise leads but deliberately limits its free tier to 3 expenses/day with ads, pushing Pro at $4.99/mo or $49.99/yr (receipt scan, currency conversion, ad-free). Tricount, Settle Up and Splid compete on “more generous free.” Your wedge is being the trip-native, generous-free option that later does what none of them do — remember the trip.");

product("3.2","EventList","Events / social (Wave 2)",
 "Guest list + RSVP + countdown for parties, dinners and weddings — a top-of-funnel feeder that creates new groups.",
 ["Create an event page; invite by text/link; RSVP tracking with no guest account",
  "Countdown, co-hosts, capacity + waitlist, date polling",
  "One-tap “split the cost” hand-off into SplitTrip"],
 ["Heavy template/design library (Evite’s moat — don’t fight there)","Ticketing/payments (that’s Eventbrite)","Print/stationery"],
 "Mostly free — Partiful has made free table stakes. Monetize only the high-value subset: premium/branded wedding pages, custom domains, or a one-time fee for keepsake event pages. Treat EventList primarily as a cheap user-acquisition feeder for SplitTrip and the trip graph, not a standalone profit center.",
 {s:["Cheap to build","Natural feeder: events create groups that then split bills","Viral by nature (every invite is a referral)"],
  w:["Almost impossible to charge for the core","Partiful is free, polished and VC-funded"],
  o:["Weddings/keepsakes are a paying niche Partiful ignores","Bridge events → trips inside one graph"],
  t:["Partiful or Evite add bill-splitting","Platform-native invites (Apple/Google) improve"]},
 "Partiful is free, ad-free and backed by ~$27M (a16z-led), already bundling RSVP, text blasts, photo albums and payment collection — with no paid tier yet. Evite monetizes premium invites at $17.99–$99.99/event and Evite Pro at $249.99/yr. Lesson: don’t monetize the invite; monetize the keepsake and use events to grow the network.");

product("3.3","TripBoard","Travel planning (Wave 2b)",
 "Real-time collaborative itinerary plus shared checklists (packing, who-brings-what) — the layer that makes the app daily-active during a trip.",
 ["Real-time collaborative day-by-day itinerary","Shared lists/checklists with assignments","Map of saved places; links from SplitTrip expenses to itinerary items"],
 ["AI suggestions/auto-planning (a “nice plus” at most, never a dependency)","Flight/hotel inbox parsing (TripIt’s domain)","Booking/affiliate engine"],
 "$30–40/yr Pro, mirroring Wanderlog’s proven $39.99/yr — but only once collaboration is genuinely sticky. Until then keep it free to build engagement.",
 {s:["Drives daily engagement during the trip","Collaboration creates lock-in for the group"],
  w:["Real-time sync adds real build cost","Wanderlog already does collab itinerary + budget + splitting"],
  o:["Bundle itinerary + bills + memories where Wanderlog has no memory layer","Engaged trip users are the audience for the recap upsell"],
  t:["Wanderlog is a strong, cheap, well-loved incumbent","Google Travel / Maps lists encroach"]},
 "Wanderlog Pro ($39.99/yr) already offers real-time collaborative editing, shared budgets and expense splitting — the strongest incumbent here. TripIt Pro ($49/yr) only organizes existing bookings with read-only sharing. Push TripBoard only if your trip users show real daily engagement; otherwise it’s a feature, not a product.");

product("3.4","TripMap","Location / GIS (Wave 3)",
 "Opt-in group live location plus the ability to pin and tag special places — the layer that quietly captures the raw material for memories.",
 ["Opt-in, privacy-first live location sharing within a trip group","Auto-log of places visited; manual pin + tag + note a “special place”","Offline capture, sync later (essential while traveling)"],
 ["Always-on tracking by default (privacy non-starter)","Standalone sale — this is a bundled capability, never a separate paid app","Social map / public discovery"],
 "Not sold standalone. Bundled into Pro. Its job is to capture the route + pinned places that make the Wave-4 recap possible; charging for it directly would lose to free platform tools.",
 {s:["Captures the unique data the recap is built from","Pins + tags add emotional context competitors lack"],
  w:["Battery, privacy, real-time infra = real cost","Weak willingness to pay on its own"],
  o:["Privacy-first, trip-scoped sharing is differentiated from always-on trackers"],
  t:["Life360 and Apple Find My own location sharing for free","Privacy backlash / OS permission tightening"]},
 "Location sharing is dominated by free, platform-level tools — Apple Find My and Life360 — and Zenly (the beloved social-location app) was shut down, showing standalone location apps struggle. So TripMap is explicitly a supporting layer: build it only after Waves 1–2 prove retention, keep it opt-in, and let it feed the recap rather than trying to win location sharing.");

product("3.5","TripReel","Memories / media (Wave 4 — the payoff)",
 "Photos and videos pinned to the trip map, stitched into an auto-generated recap video — the emotional climax and the growth engine.",
 ["Attach photos/videos/notes to pinned places and days","Auto-build a route-animated highlight reel at trip’s end","One-tap share of the recap (this is the marketing loop)"],
 ["Heavy in-app editor (keep templated/automatic)","AI auto-curation — a later “nice plus,” not required for v1","Social feed / public profiles"],
 "Highest-margin wave. One-time recap unlock and/or printed photo book — the proven Polarsteps model (books from €36). Charge at the emotional peak (trip’s end) when willingness to pay is highest, and let every shared recap recruit new users for free.",
 {s:["Strong, proven willingness to pay at the emotional peak","Shared recaps are the cheapest possible acquisition","Highest strategic fit — it is the vision’s payoff"],
  w:["Video rendering, storage and media pipeline are costly","Long path before this wave can ship"],
  o:["No bill-splitter offers memories; no memory app offers bills — you own the loop","Physical books = high-margin one-time revenue"],
  t:["Polarsteps, Relive and a new “TripReel” app already exist","Google Photos “Memories” is free and automatic"]},
 "The endgame is validated and contested. Polarsteps (free app) monetizes printed travel books (€36–€150) and a yearly “Unpacked” recap; Relive turns GPS routes into 3D flyover videos, free with a €6.99/mo Plus tier; an app literally named “TripReel” is already on the App Store. Note the name conflict — you’ll need a different brand. Your edge isn’t a better recap in isolation; it’s that the recap is fed by the bills, itinerary and map already in one app.");

product("3.6","The Suite","Integrated platform (Wave 5 — the endgame)",
 "The all-in-one trip super-app: plan, split bills, share location, capture memories, and relive it — one group, one app, one loop.",
 ["Unifies all prior modules under one trip object and one group","Single Pro bundle across modules","Cross-module intelligence (e.g., expenses auto-pin to places on the map)"],
 ["Building before each module has proven demand independently","Trying to win every segment head-on simultaneously"],
 "Single Pro subscription plus high-margin one-time recap/book sales — multiple revenue streams over the same user base. Only assemble once the pieces have each earned their place.",
 {s:["Defensible: no incumbent owns the whole trip loop","Multiple revenue streams over one acquired user","Compounding network effects from every prior wave"],
  w:["Most expensive and slowest to build","Highest execution and focus risk"],
  o:["Own “the trip” end-to-end where rivals own only one slice"],
  t:["A well-funded incumbent (Wanderlog, Splitwise) bundles first","Scope creep dilutes quality across modules"]},
 "No competitor currently spans the full loop: Splitwise has bills but no memories; Polarsteps has memories but no bills; Wanderlog has planning + splitting but no recap; Partiful has events only. The Suite is defensible precisely because assembling the whole loop — funded incrementally by each prior wave — is what none of them have done.");

children.push(new Paragraph({children:[new PageBreak()]}));
children.push(H1("4. Competitor landscape by segment"));
children.push(P("Current pricing and positioning (May 2026). Sources listed in Section 8."));
children.push(table(
 [1700,2300,1860,3500],
 [hcell("Segment",1700),hcell("Key players",2300),hcell("Pricing",1860),hcell("Your angle",3500)],
 [
  ["Bill splitting","Splitwise, Tricount, Settle Up, Splid","Splitwise free (3/day cap); Pro $4.99/mo or $49.99/yr","Trip-native + generous free; later: the only one that remembers the trip"],
  ["Trip planning","Wanderlog, TripIt","Wanderlog Pro $39.99/yr; TripIt Pro $49/yr","Bundle planning with bills + memories (Wanderlog has no memory layer)"],
  ["Event / RSVP","Partiful, Evite, Paperless Post","Partiful free; Evite premium $17.99–$99.99/event, Pro $249.99/yr","Don’t monetize invites — use them to grow the group graph; charge on keepsakes"],
  ["Location sharing","Apple Find My, Life360 (Zenly shut down)","Free / platform-owned","Don’t compete; offer opt-in, trip-scoped sharing as a feeding layer"],
  ["Memories / recap","Polarsteps, Relive, TripReel","Polarsteps books €36+; Relive Plus €6.99/mo","Recap fed by your own bills + itinerary + map = a loop none of them close"],
 ]));

children.push(H1("5. Strategic synthesis"));
children.push(P("The crowded, low-margin end (bill splitting) is your cheapest, fastest entry and your viral engine. The expensive, high-margin end (memories/recap) is your payoff and growth loop — but you only earn the right and the cash to build it after the wedge proves people stick. The genuine white space is the full loop: every incumbent owns exactly one slice, and assembling the whole thing incrementally is the defensible move."));
children.push(P("Critically, none of these products depends on AI. AI is at most a “nice plus” later — auto-curating recap clips, suggesting itinerary items, or categorizing expenses — never a build dependency or a reason for the product to exist."));

children.push(H1("6. SWOT and RICE — how to read them together"));
children.push(P("SWOT (per product, Section 3) is qualitative: it tells you why a product wins or loses and where the risks sit. RICE and the weighted scorecard are quantitative rankers. Use SWOT to decide how to play a product, and the scores to decide which to build first."));

children.push(H1("7. Recommended ship sequence — and why the rankings differ"));
children.push(P("The weighted model and RICE agree on SplitTrip at #1 and TripMap at last, but they disagree in the middle. RICE pushes EventList up (cheap, broad reach) and pushes TripReel/TripBoard down (high effort hurts the ÷Effort term). The weighted model lifts TripReel because you weighted strategic fit highly. Both are “right” — RICE optimizes for efficient near-term wins; your weights optimize for the long-term vision. The sequence below honors both, plus build dependencies."));
[
 ["Wave 1 — SplitTrip","Weeks 1–4. Ship the wedge, turn on the paid upgrade early, watch invite-activation and free→paid. This funds everything else."],
 ["Wave 2 — EventList","Weeks 5–8. Cheap feeder that creates new groups; keep core free, test keepsake/wedding monetization."],
 ["Wave 2b — TripBoard","Weeks 7–12. Add collaborative itinerary to lift daily engagement; only push Pro if engagement is real (Wanderlog is strong)."],
 ["Wave 3 — TripMap","Months 4–6. Opt-in location + place pins. Bundled, not sold alone. Built now because Wave 4 needs its data."],
 ["Wave 4 — TripReel","Months 6–9. The recap payoff and viral loop; monetize via one-time unlock and printed books at the emotional peak."],
 ["Wave 5 — The Suite","Months 9+. Assemble the full loop into one Pro bundle once each module has independently proven demand."],
].forEach(([h,t])=>{ children.push(H3(h)); children.push(P(t)); });
children.push(P("Kill/Go signals for each wave are in the “Build Sequence” tab of the companion spreadsheet.", {run:{italics:true,size:18,color:GREY}}));

children.push(H1("8. Sources"));
const src = [
 ["Splitwise pricing (Free vs Pro), 2026","https://www.splitwise.com/subscriptions/new"],
 ["Polarsteps — travel book pricing","https://support.polarsteps.com/hc/en-us/articles/24003935464466-What-is-the-price-of-a-Travel-Book"],
 ["Polarsteps — plan, track, relive","https://www.polarsteps.com/"],
 ["Partiful vs Evite (2026)","https://blog.mixily.com/evite-vs-partiful/"],
 ["Partiful (free invitations)","https://partiful.com/"],
 ["Wanderlog vs TripIt pricing (2026)","https://monkeyeatingmango.com/blog/wanderlog-pricing-2026/"],
 ["Relive — route recap videos / pricing","https://play.google.com/store/apps/details?id=cc.relive.reliveapp&hl=en_US"],
 ["TripReel — existing App Store listing","https://apps.apple.com/us/app/tripreel-travel-recap-videos/id6757102726"],
].map(([t,u])=>new Paragraph({ spacing:{after:60}, children:[
  new ExternalHyperlink({ children:[new TextRun({text:t,style:"Hyperlink",font:FONT,size:20})], link:u }) ]}));
src.forEach(s=>children.push(s));

const doc = new Document({
  styles:{ default:{document:{run:{font:FONT,size:22}}},
    paragraphStyles:[
      {id:"Heading1",name:"Heading 1",basedOn:"Normal",next:"Normal",quickFormat:true,
        run:{size:30,bold:true,font:FONT,color:NAVY},paragraph:{spacing:{before:280,after:140},outlineLevel:0}},
      {id:"Heading2",name:"Heading 2",basedOn:"Normal",next:"Normal",quickFormat:true,
        run:{size:26,bold:true,font:FONT,color:BLUE},paragraph:{spacing:{before:220,after:120},outlineLevel:1}},
      {id:"Heading3",name:"Heading 3",basedOn:"Normal",next:"Normal",quickFormat:true,
        run:{size:22,bold:true,font:FONT,color:"333333"},paragraph:{spacing:{before:140,after:60},outlineLevel:2}},
    ]},
  numbering:{ config:[
    {reference:"bul",levels:[{level:0,format:LevelFormat.BULLET,text:"•",alignment:AlignmentType.LEFT,
      style:{paragraph:{indent:{left:540,hanging:260}}}}]} ]},
  sections:[{ properties:{ page:{ size:{width:12240,height:15840}, margin:{top:1440,right:1440,bottom:1440,left:1440} } },
    children }]
});
Packer.toBuffer(doc).then(buf=>{ fs.writeFileSync("/sessions/tender-quirky-bardeen/mnt/outputs/Trip_App_Roadmap_and_Competitor_Analysis.docx", buf); console.log("doc saved"); });

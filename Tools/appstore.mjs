#!/usr/bin/env node
// Fills in the App Store Connect listing for Lookout from AppStore/metadata.md, uploads screenshots,
// attaches the latest processed builds and submits for review.
//
// Usage: node Tools/appstore.mjs <command> [--platform ios|tvos|all]
//   metadata     name/subtitle/privacy URL, categories, version text (description, keywords, …)
//   screenshots  replace the screenshot sets with AppStore/screenshots/{iphone,ipad,tv}-*.png
//   attach       attach the newest processed build to each platform's version
//   submit       submit both platform versions for review
//   release      automatic release after approval, or --manual to release by hand
//   testflight   create the "Primary Tech" external group if needed, beta info, What to Test, add builds, submit for beta review
//   status       print versions, builds and review state
// Auth: App Store Connect API key at ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8.
import { createPrivateKey, sign, createHash } from "node:crypto";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const KEY_ID = process.env.ASC_KEY_ID || "Z5YD293RLM";
const ISSUER_ID = process.env.ASC_ISSUER_ID || "69a6de84-dcf8-47e3-e053-5b8c7c11a4d1";
const BUNDLE_ID = "fm.beard.Lookout";
const VERSION = "1.0";
const BUILD = "3";
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const API = "https://api.appstoreconnect.apple.com/v1";

// ---------- auth ----------
const b64url = (b) => Buffer.from(b).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
function token() {
  const key = createPrivateKey(readFileSync(join(homedir(), ".appstoreconnect/private_keys", `AuthKey_${KEY_ID}.p8`)));
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: KEY_ID, typ: "JWT" }));
  const payload = b64url(JSON.stringify({ iss: ISSUER_ID, iat: now, exp: now + 1100, aud: "appstoreconnect-v1" }));
  const sig = sign("sha256", Buffer.from(`${header}.${payload}`), { key, dsaEncoding: "ieee-p1363" });
  return `${header}.${payload}.${b64url(sig)}`;
}
async function api(method, path, body, raw) {
  const res = await fetch(path.startsWith("http") ? path : API + path, {
    method,
    headers: { Authorization: `Bearer ${token()}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return null;
  const text = await res.text();
  let json; try { json = JSON.parse(text); } catch { json = text; }
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status}: ${typeof json === "string" ? json : JSON.stringify(json.errors ?? json)}`);
  return raw ? json : json;
}
const get = (p) => api("GET", p), post = (p, b) => api("POST", p, b), patch = (p, b) => api("PATCH", p, b), del = (p) => api("DELETE", p);
async function all(path) {
  let out = [], next = path;
  while (next) { const page = await get(next); out = out.concat(page.data); next = page.links?.next; }
  return out;
}

// ---------- metadata.md ----------
const md = readFileSync(join(ROOT, "AppStore/metadata.md"), "utf8");
const field = (label) => { const m = md.match(new RegExp(`\\*\\*${label}[^*]*\\*\\*\\s*(.+)`)); return m ? m[1].trim() : null; };
const block = (label) => { const m = md.match(new RegExp(`\\*\\*${label}[^*]*\\*\\*\\n([\\s\\S]*?)\\n\\n(?=\\*\\*|## )`)); return m ? m[1].trim() : null; };
const META = {
  subtitle: field("Subtitle \\(30\\):"),
  privacyPolicyUrl: field("Privacy Policy URL:"),
  supportUrl: field("Support URL:"),
  marketingUrl: field("Marketing URL:"),
  copyright: field("Copyright:"),
  promotionalText: block("Promotional text"),
  description: block("Description"),
  keywords: block("Keywords"),
  whatsNew: block("What's New"),
  whatToTest: block("What to Test"),
  reviewNotes: (md.match(/- \*\*Notes:\*\*\n([\s\S]*?)\n\n## /) || [])[1]?.replace(/\n  /g, " ").trim(),
};

// ---------- lookups ----------
async function app() {
  const apps = await get(`/apps?filter[bundleId]=${BUNDLE_ID}`);
  if (!apps.data.length) throw new Error(`No app with bundle id ${BUNDLE_ID}`);
  return apps.data[0];
}
const PLATFORMS = { ios: "IOS", tvos: "TV_OS" };
function wanted() {
  const i = process.argv.indexOf("--platform");
  const p = i > 0 ? process.argv[i + 1] : "all";
  return p === "all" ? Object.values(PLATFORMS) : [PLATFORMS[p]];
}
async function version(appId, platform) {
  const versions = await get(`/apps/${appId}/appStoreVersions?filter[platform]=${platform}&limit=5`);
  let v = versions.data.find((x) => x.attributes.versionString === VERSION) ?? versions.data.find((x) => !["READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION"].includes(x.attributes.appStoreState));
  if (!v) {
    v = (await post("/appStoreVersions", { data: { type: "appStoreVersions", attributes: { platform, versionString: VERSION, copyright: META.copyright }, relationships: { app: { data: { type: "apps", id: appId } } } } })).data;
    console.log(`created ${platform} version ${VERSION}`);
  }
  return v;
}

/// The review contact phone already on file for one of Stephen's other apps.
async function reviewPhoneFromOtherApp() {
  for (const bundle of ["fm.beard.Leveler", "fm.beard.Transcriber", "fm.beard.Captioner", "fm.beard.KanDo", "fm.beard.HomePad"]) {
    const apps = await get(`/apps?filter[bundleId]=${bundle}`).catch(() => null);
    for (const other of apps?.data ?? []) {
      const versions = await get(`/apps/${other.id}/appStoreVersions?limit=3`).catch(() => null);
      for (const v of versions?.data ?? []) {
        const d = await get(`/appStoreVersions/${v.id}/appStoreReviewDetail`).catch(() => null);
        if (d?.data?.attributes?.contactPhone) return d.data.attributes.contactPhone;
      }
    }
  }
  return null;
}

// ---------- commands ----------
async function metadata() {
  const a = await app();
  const infos = await get(`/apps/${a.id}/appInfos`);
  const info = infos.data.find((x) => x.attributes.appStoreState !== "READY_FOR_SALE") ?? infos.data[0];
  for (const each of infos.data) {
    const locs = await get(`/appInfos/${each.id}/appInfoLocalizations`);
    for (const loc of locs.data.filter((l) => l.attributes.locale === "en-US")) {
      // App Store Connect drops privacyPolicyUrl when it is patched together with other
      // attributes on a fresh app info record, so send it on its own.
      try {
        await patch(`/appInfoLocalizations/${loc.id}`, { data: { type: "appInfoLocalizations", id: loc.id, attributes: { subtitle: META.subtitle } } });
        await patch(`/appInfoLocalizations/${loc.id}`, { data: { type: "appInfoLocalizations", id: loc.id, attributes: { privacyPolicyUrl: META.privacyPolicyUrl } } });
        console.log(`app info localization updated (${each.attributes.appStoreState}):`, loc.attributes.name);
      } catch (e) { console.log(`app info localization ${loc.id}: ${e.message.slice(0, 200)}`); }
    }
  }
  const cats = await get(`/appCategories?filter[platforms]=IOS,TV_OS&limit=200`);
  const cat = (id) => cats.data.find((c) => c.id === id) ? { type: "appCategories", id } : null;
  await patch(`/appInfos/${info.id}`, { data: { type: "appInfos", id: info.id, relationships: {
    primaryCategory: { data: cat("UTILITIES") }, secondaryCategory: { data: cat("LIFESTYLE") } } } });
  console.log("categories set");
  for (const platform of wanted()) {
    const v = await version(a.id, platform);
    await patch(`/appStoreVersions/${v.id}`, { data: { type: "appStoreVersions", id: v.id, attributes: { copyright: META.copyright, versionString: VERSION } } });
    const vlocs = await get(`/appStoreVersions/${v.id}/appStoreVersionLocalizations`);
    let loc = vlocs.data.find((l) => l.attributes.locale === "en-US");
    const attrs = { description: META.description, keywords: META.keywords, promotionalText: META.promotionalText, supportUrl: META.supportUrl, marketingUrl: META.marketingUrl, whatsNew: META.whatsNew };
    // A first release has no "What's New"; App Store Connect rejects the field, so drop it on that error.
    const save = async (a) => {
      if (!loc) loc = (await post("/appStoreVersionLocalizations", { data: { type: "appStoreVersionLocalizations", attributes: { locale: "en-US", ...a }, relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: v.id } } } } })).data;
      else await patch(`/appStoreVersionLocalizations/${loc.id}`, { data: { type: "appStoreVersionLocalizations", id: loc.id, attributes: a } });
    };
    try { await save(attrs); } catch (e) {
      if (!/whatsNew/.test(e.message)) throw e;
      const { whatsNew, ...rest } = attrs; await save(rest);
    }
    // Review details
    const details = await get(`/appStoreVersions/${v.id}/appStoreReviewDetail`).catch(() => null);
    const review = { contactFirstName: "Stephen", contactLastName: "Robles", contactEmail: "steve@beard.fm", demoAccountRequired: false, notes: META.reviewNotes };
    const phone = process.env.ASC_PHONE || await reviewPhoneFromOtherApp();
    if (phone) review.contactPhone = phone;
    if (details?.data) await patch(`/appStoreReviewDetails/${details.data.id}`, { data: { type: "appStoreReviewDetails", id: details.data.id, attributes: review } });
    else await post("/appStoreReviewDetails", { data: { type: "appStoreReviewDetails", attributes: review, relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: v.id } } } } });
    console.log(`${platform} ${VERSION}: text and review details set`);
  }
}

const DISPLAY_TYPES = { tv: "APP_APPLE_TV", iphone: "APP_IPHONE_67", ipad: "APP_IPAD_PRO_3GEN_129" };
async function screenshots() {
  const a = await app();
  for (const platform of wanted()) {
    const v = await version(a.id, platform);
    const vlocs = await get(`/appStoreVersions/${v.id}/appStoreVersionLocalizations`);
    const loc = vlocs.data.find((l) => l.attributes.locale === "en-US");
    const kinds = platform === "TV_OS" ? ["tv"] : ["iphone", "ipad"];
    for (const kind of kinds) {
      const files = readdirSync(join(ROOT, "AppStore/screenshots")).filter((f) => f.startsWith(kind + "-") && f.endsWith(".png")).sort();
      if (!files.length) continue;
      const sets = await get(`/appStoreVersionLocalizations/${loc.id}/appScreenshotSets`);
      const stale = { iphone: ["APP_IPHONE_61", "APP_IPHONE_65"], ipad: ["APP_IPAD_PRO_129"], tv: [] }[kind];
      for (const old of sets.data.filter((s) => stale.includes(s.attributes.screenshotDisplayType))) await del(`/appScreenshotSets/${old.id}`);
      let set = sets.data.find((s) => s.attributes.screenshotDisplayType === DISPLAY_TYPES[kind]);
      if (set) { for (const shot of (await get(`/appScreenshotSets/${set.id}/appScreenshots`)).data) await del(`/appScreenshots/${shot.id}`); }
      else set = (await post("/appScreenshotSets", { data: { type: "appScreenshotSets", attributes: { screenshotDisplayType: DISPLAY_TYPES[kind] }, relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: loc.id } } } } })).data;
      for (const file of files) {
        const data = readFileSync(join(ROOT, "AppStore/screenshots", file));
        const shot = (await post("/appScreenshots", { data: { type: "appScreenshots", attributes: { fileName: file, fileSize: data.length }, relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: set.id } } } } })).data;
        for (const op of shot.attributes.uploadOperations) {
          const chunk = data.subarray(op.offset, op.offset + op.length);
          const headers = Object.fromEntries(op.requestHeaders.map((h) => [h.name, h.value]));
          const r = await fetch(op.url, { method: op.method, headers, body: chunk });
          if (!r.ok) throw new Error(`upload chunk failed: ${r.status}`);
        }
        await patch(`/appScreenshots/${shot.id}`, { data: { type: "appScreenshots", id: shot.id, attributes: { uploaded: true, sourceFileChecksum: createHash("md5").update(data).digest("hex") } } });
        console.log(`${platform} ${kind}: uploaded ${file}`);
      }
    }
  }
}

async function attach() {
  const a = await app();
  for (const platform of wanted()) {
    const v = await version(a.id, platform);
    // Newest processed build for this platform (build numbers may differ between platforms).
    const builds = await get(`/builds?filter[app]=${a.id}&filter[preReleaseVersion.platform]=${platform}&sort=-uploadedDate&limit=10`);
    const build = builds.data.find((b) => b.attributes.processingState === "VALID");
    if (!build) { console.log(`${platform}: no processed build yet (${builds.data.map((b) => b.attributes.version + ":" + b.attributes.processingState).join(", ") || "none"})`); continue; }
    await patch(`/appStoreVersions/${v.id}/relationships/build`, { data: { type: "builds", id: build.id } });
    console.log(`${platform}: attached build ${build.attributes.version} (${build.id})`);
  }
}

async function submit() {
  const a = await app();
  for (const platform of wanted()) {
    const v = await version(a.id, platform);
    if (["WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"].includes(v.attributes.appStoreState)) {
      console.log(`${platform} ${VERSION}: already ${v.attributes.appStoreState}`); continue;
    }
    // Reuse a draft submission if an earlier attempt left one open.
    const open = await get(`/apps/${a.id}/reviewSubmissions?filter[platform]=${platform}&filter[state]=READY_FOR_REVIEW&limit=5`);
    let sub = open.data[0];
    if (!sub) sub = (await post("/reviewSubmissions", { data: { type: "reviewSubmissions", attributes: { platform }, relationships: { app: { data: { type: "apps", id: a.id } } } } })).data;
    const items = await get(`/reviewSubmissions/${sub.id}/items`);
    if (!items.data.length) {
      await post("/reviewSubmissionItems", { data: { type: "reviewSubmissionItems", relationships: { reviewSubmission: { data: { type: "reviewSubmissions", id: sub.id } }, appStoreVersion: { data: { type: "appStoreVersions", id: v.id } } } } });
    }
    await patch(`/reviewSubmissions/${sub.id}`, { data: { type: "reviewSubmissions", id: sub.id, attributes: { submitted: true } } });
    console.log(`${platform}: submitted for review (${sub.id})`);
  }
}

/// Reports whether the fields App Review requires are present on the 1.1 versions.
async function verify() {
  const a = await app();
  const infos = await get(`/apps/${a.id}/appInfos`);
  for (const info of infos.data) {
    const locs = await get(`/appInfos/${info.id}/appInfoLocalizations`);
    for (const l of locs.data) console.log(`appInfo ${info.id} (${info.attributes.appStoreState}) ${l.attributes.locale}: privacyPolicyUrl=${l.attributes.privacyPolicyUrl}`);
  }
  for (const platform of wanted()) {
    const v = await version(a.id, platform);
    const vlocs = await get(`/appStoreVersions/${v.id}/appStoreVersionLocalizations`);
    for (const l of vlocs.data) console.log(`${platform} ${VERSION} ${l.attributes.locale}: whatsNew=${JSON.stringify((l.attributes.whatsNew || "").slice(0, 40))} releaseType=${v.attributes.releaseType}`);
  }
}

/// Age rating (nothing applies), privacy (data not collected), content rights, and a free price.
async function prepare() {
  const a = await app();
  await patch(`/apps/${a.id}`, { data: { type: "apps", id: a.id, attributes: { contentRightsDeclaration: "DOES_NOT_USE_THIRD_PARTY_CONTENT" } } });
  console.log("content rights: does not use third-party content");

  for (const platform of wanted()) {
    const v = await version(a.id, platform);
    // The version's declaration shares the version's id; the app-info one is a separate record. Set both.
    const infos = await get(`/apps/${a.id}/appInfos`);
    const infoDecl = await get(`/appInfos/${infos.data[0].id}/ageRatingDeclaration`).catch(() => null);
    const declIds = [v.id, infoDecl?.data?.id].filter(Boolean);
    const none = ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "horrorOrFearThemes", "matureOrSuggestiveThemes",
      "medicalOrTreatmentInformation", "profanityOrCrudeHumor", "sexualContentGraphicAndNudity", "sexualContentOrNudity", "gunsOrOtherWeapons",
      "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"];
    const no = ["gambling", "unrestrictedWebAccess", "lootBox", "advertising", "messagingAndChat", "userGeneratedContent", "parentalControls", "healthOrWellnessTopics"];
    const attrs = { ageAssurance: false, kidsAgeBand: null };
    for (const k of none) attrs[k] = "NONE";
    for (const k of no) attrs[k] = false;
    for (const id of declIds) {
      try {
        await patch(`/ageRatingDeclarations/${id}`, { data: { type: "ageRatingDeclarations", id, attributes: attrs } });
        console.log(`${platform}: age rating declared on ${id} (nothing applies)`);
      } catch (e) { if (!/NOT_FOUND/.test(e.message)) console.log(`${platform}: age rating on ${id}: ${e.message.slice(0, 600)}`); }
    }
  }

  // App privacy ("Data Not Collected") has no public API; it is set once in App Store Connect's App Privacy section.
  console.log("privacy: set 'Data Not Collected' in App Store Connect › App Privacy and publish (no API)");

  // Pricing: free, base territory USA.
  const schedule = await get(`/apps/${a.id}/appPriceSchedule`).catch(() => null);
  const manual = schedule?.data ? await get(`/appPriceSchedules/${schedule.data.id}/manualPrices?limit=5`).catch(() => null) : null;
  if (!manual?.data?.length) {
    const points = await get(`/apps/${a.id}/appPricePoints?filter[territory]=USA&limit=200`);
    const free = points.data.find((p) => Number(p.attributes.customerPrice) === 0);
    if (!free) throw new Error("no free price point found");
    await post("/appPriceSchedules", { data: { type: "appPriceSchedules", relationships: {
      app: { data: { type: "apps", id: a.id } }, baseTerritory: { data: { type: "territories", id: "USA" } },
      manualPrices: { data: [{ type: "appPrices", id: "${price-free}" }] } } },
      included: [{ type: "appPrices", id: "${price-free}", attributes: { startDate: null }, relationships: { appPricePoint: { data: { type: "appPricePoints", id: free.id } } } }] });
    console.log("pricing: free in all territories (base USA)");
  } else {
    console.log("pricing: already set");
  }
}

/// Pulls a platform's pending review submission so a new build can be attached and resubmitted.
async function cancel() {
  const a = await app();
  const subs = await get(`/apps/${a.id}/reviewSubmissions?filter[state]=WAITING_FOR_REVIEW,READY_FOR_REVIEW,UNRESOLVED_ISSUES&limit=10`);
  for (const platform of wanted()) {
    const sub = subs.data.find((x) => x.attributes.platform === platform);
    if (!sub) { console.log(`${platform}: nothing waiting for review`); continue; }
    await patch(`/reviewSubmissions/${sub.id}`, { data: { type: "reviewSubmissions", id: sub.id, attributes: { canceled: true } } });
    console.log(`${platform}: review submission ${sub.id} cancelled (${sub.attributes.state})`);
  }
}

async function status() {
  const a = await app();
  console.log(`${a.attributes.name} (${a.id})`);
  for (const platform of Object.values(PLATFORMS)) {
    const versions = await get(`/apps/${a.id}/appStoreVersions?filter[platform]=${platform}&limit=5`);
    for (const v of versions.data) console.log(`  ${platform} ${v.attributes.versionString}: ${v.attributes.appStoreState}`);
    const builds = await get(`/builds?filter[app]=${a.id}&filter[preReleaseVersion.platform]=${platform}&sort=-uploadedDate&limit=5`);
    for (const b of builds.data) console.log(`    build ${b.attributes.version}: ${b.attributes.processingState}`);
  }
}

/// Release type: automatic after App Review approval, or `--manual` to release by hand.
async function release() {
  const a = await app();
  const manual = process.argv.includes("--manual");
  for (const platform of wanted()) {
    const v = await version(a.id, platform);
    await patch(`/appStoreVersions/${v.id}`, { data: { type: "appStoreVersions", id: v.id, attributes: { releaseType: manual ? "MANUAL" : "AFTER_APPROVAL" } } });
    console.log(`${platform} ${VERSION}: release type set to ${manual ? "manual" : "automatic (after approval)"}`);
  }
}

/// Export compliance on the newest builds, "What to Test" notes, and the external TestFlight group.
async function testflight() {
  const a = await app();
  const groupName = process.env.TF_GROUP || "Primary Tech";
  const groups = await get(`/apps/${a.id}/betaGroups?limit=50`);
  let group = groups.data.find((g) => g.attributes.name === groupName);
  if (!group) {
    group = (await post("/betaGroups", { data: { type: "betaGroups", attributes: { name: groupName, isInternalGroup: false, publicLinkEnabled: true, publicLinkLimitEnabled: false, feedbackEnabled: true }, relationships: { app: { data: { type: "apps", id: a.id } } } } })).data;
    console.log(`created external TestFlight group "${groupName}"`);
  }
  // Beta App Information (description + feedback email) and Beta App Review contact, required before external review.
  const betaLocs = await get(`/apps/${a.id}/betaAppLocalizations`);
  const betaLoc = betaLocs.data.find((l) => l.attributes.locale === "en-US");
  const betaAttrs = { description: META.promotionalText + " " + (META.description.split("\n\n")[0] || ""), feedbackEmail: "steve@beard.fm", marketingUrl: META.marketingUrl, privacyPolicyUrl: META.privacyPolicyUrl };
  if (betaLoc) await patch(`/betaAppLocalizations/${betaLoc.id}`, { data: { type: "betaAppLocalizations", id: betaLoc.id, attributes: betaAttrs } });
  else await post("/betaAppLocalizations", { data: { type: "betaAppLocalizations", attributes: { locale: "en-US", ...betaAttrs }, relationships: { app: { data: { type: "apps", id: a.id } } } } });
  const betaReview = await get(`/apps/${a.id}/betaAppReviewDetail`).catch(() => null);
  const phone = process.env.ASC_PHONE || await reviewPhoneFromOtherApp();
  const contact = { contactFirstName: "Stephen", contactLastName: "Robles", contactEmail: "steve@beard.fm", demoAccountRequired: false, notes: META.reviewNotes, ...(phone ? { contactPhone: phone } : {}) };
  if (betaReview?.data) await patch(`/betaAppReviewDetails/${betaReview.data.id}`, { data: { type: "betaAppReviewDetails", id: betaReview.data.id, attributes: contact } });
  console.log("beta app information and review contact set");
  for (const platform of wanted()) {
    const builds = await get(`/builds?filter[app]=${a.id}&filter[preReleaseVersion.platform]=${platform}&filter[version]=${BUILD}&sort=-uploadedDate&limit=5`);
    const build = builds.data.find((b) => b.attributes.processingState === "VALID");
    if (!build) { console.log(`${platform}: build ${BUILD} not processed yet (${builds.data.map((b) => b.attributes.processingState).join(", ") || "none"})`); continue; }
    if (build.attributes.usesNonExemptEncryption === null) {
      await patch(`/builds/${build.id}`, { data: { type: "builds", id: build.id, attributes: { usesNonExemptEncryption: false } } });
      console.log(`${platform}: export compliance set (no non-exempt encryption)`);
    }
    const locs = await get(`/builds/${build.id}/betaBuildLocalizations`);
    const loc = locs.data.find((l) => l.attributes.locale === "en-US");
    const toTest = META.whatToTest || META.whatsNew;
    if (loc) await patch(`/betaBuildLocalizations/${loc.id}`, { data: { type: "betaBuildLocalizations", id: loc.id, attributes: { whatsNew: toTest } } });
    else await post("/betaBuildLocalizations", { data: { type: "betaBuildLocalizations", attributes: { locale: "en-US", whatsNew: toTest }, relationships: { build: { data: { type: "builds", id: build.id } } } } });
    await post(`/betaGroups/${group.id}/relationships/builds`, { data: [{ type: "builds", id: build.id }] });
    console.log(`${platform}: build ${BUILD} added to "${groupName}" with What to Test`);
    const link = (await get(`/betaGroups/${group.id}`)).data.attributes.publicLink;
    if (link) console.log(`public link: ${link}`);
    const review = await get(`/builds/${build.id}/betaAppReviewSubmission`).catch(() => null);
    if (!review?.data) {
      try {
        await post("/betaAppReviewSubmissions", { data: { type: "betaAppReviewSubmissions", relationships: { build: { data: { type: "builds", id: build.id } } } } });
        console.log(`${platform}: submitted build ${BUILD} for beta app review`);
      } catch (e) { console.log(`${platform}: beta review: ${e.message.slice(0, 300)}`); }
    } else console.log(`${platform}: beta app review already ${review.data.attributes.betaReviewState}`);
  }
}

const commands = { metadata, screenshots, attach, submit, status, prepare, cancel, release, testflight, verify };
const cmd = commands[process.argv[2]];
if (!cmd) { console.error("usage: node Tools/appstore.mjs status|metadata|attach|release|testflight|submit|screenshots|prepare|cancel [--platform ios|mac|all]"); process.exit(1); }
cmd().catch((e) => { console.error(e.message); process.exit(1); });

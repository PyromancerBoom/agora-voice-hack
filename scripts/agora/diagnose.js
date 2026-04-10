/**
 * Isolates each dependency: Mistral, ElevenLabs, Agora RTC token, join payload shape.
 * Run from repo root: npm run agora:diagnose
 * Optional: npm run agora:diagnose -- --live   (starts + stops one real agent; uses quota)
 */

const { loadEnvFile } = require("./load-env");
loadEnvFile();

const { ExpiresIn, generateRtcToken, generateConvoAIToken } = require(
  "agora-agent-server-sdk"
);
const {
  buildLlmConfig,
  buildTtsConfig,
  resolveVoiceIdForNpc,
} = require("./npc-manager");
const npcProfiles = require("./data/npc-profiles.json");

function mask(v) {
  if (!v || typeof v !== "string") return v ? "(set)" : "(missing)";
  if (v.length <= 8) return "***";
  return `${v.slice(0, 4)}…${v.slice(-4)} (${v.length} chars)`;
}

function redactDeep(obj) {
  return JSON.parse(
    JSON.stringify(obj, (k, val) => {
      if (k === "api_key" || k === "key") {
        return typeof val === "string" ? mask(val) : val;
      }
      return val;
    })
  );
}

async function step(name, fn) {
  process.stdout.write(`\n━━ ${name} ━━\n`);
  try {
    await fn();
  } catch (e) {
    console.error("FAIL:", e.message || e);
  }
}

async function testMistral() {
  const key = process.env.MISTRAL_API_KEY;
  if (!key) {
    console.log("SKIP: MISTRAL_API_KEY not set");
    return;
  }
  const model = process.env.LLM_MODEL || "mistral-small-latest";
  const res = await fetch("https://api.mistral.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      messages: [{ role: "user", content: "Reply with exactly: OK" }],
      max_tokens: 16,
      stream: false,
    }),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${res.status} ${text.slice(0, 400)}`);
  }
  const data = JSON.parse(text);
  const content = data.choices?.[0]?.message?.content;
  console.log("OK: Mistral replied:", JSON.stringify(content));
}

async function testOpenAI() {
  const key = process.env.OPENAI_API_KEY;
  if (!key) {
    console.log("SKIP: OPENAI_API_KEY not set");
    return;
  }
  const model = process.env.LLM_MODEL || "gpt-4o-mini";
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      messages: [{ role: "user", content: "Reply with exactly: OK" }],
      max_tokens: 16,
      stream: false,
    }),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${res.status} ${text.slice(0, 400)}`);
  }
  const data = JSON.parse(text);
  const content = data.choices?.[0]?.message?.content;
  console.log("OK: OpenAI replied:", JSON.stringify(content));
}

async function testElevenLabs() {
  const key = process.env.ELEVENLABS_API_KEY;
  if (!key) {
    console.log("SKIP: ELEVENLABS_API_KEY not set");
    return;
  }
  const res = await fetch("https://api.elevenlabs.io/v1/user", {
    headers: { "xi-api-key": key },
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`${res.status} ${text.slice(0, 400)}`);
  }
  const data = JSON.parse(text);
  console.log(
    "OK: ElevenLabs user/subscription:",
    data.subscription?.tier || data.subscription?.tier_name || "see raw"
  );
  const butler = npcProfiles.find((p) => p.npcId === "butler");
  const voiceId = await resolveVoiceIdForNpc(butler);
  console.log(
    "OK: Butler spawn will use voice_id (after env/profile/fallback chain):",
    voiceId
  );
}

function testAgoraTokens() {
  const appId = process.env.AGORA_APP_ID;
  const cert = process.env.AGORA_APP_CERTIFICATE;
  if (!appId || !cert) {
    console.log("SKIP: AGORA_APP_ID / AGORA_APP_CERTIFICATE missing");
    return;
  }
  const channel = "diag-channel";
  const rtc = generateRtcToken({
    appId,
    appCertificate: cert,
    channel,
    uid: 5001,
    expirySeconds: 3600,
  });
  const convo = generateConvoAIToken({
    appId,
    appCertificate: cert,
    channelName: channel,
    account: "1001",
    tokenExpire: ExpiresIn.HOUR,
  });
  console.log("OK: RTC token length", rtc.length, "| ConvoAI token length", convo.length);
}

async function printPayloadShape() {
  const profile = npcProfiles.find((p) => p.npcId === "butler");
  const llm = buildLlmConfig("Diagnostic stub prompt.");
  const voiceId = await resolveVoiceIdForNpc(profile);
  const tts = buildTtsConfig(voiceId);
  console.log("LLM (redacted):\n", JSON.stringify(redactDeep(llm), null, 2));
  console.log("TTS (redacted):\n", JSON.stringify(redactDeep(tts), null, 2));
}

async function testLiveJoin() {
  const { startSession, stopSession } = require("./agora-service");
  const profile = npcProfiles.find((p) => p.npcId === "butler");
  const voiceId = await resolveVoiceIdForNpc(profile);
  const channel = `diag-live-${Date.now()}`;
  console.log("Starting agent on channel", channel, "…");
  const result = await startSession({
    channel,
    playerUid: 5001,
    agentUid: 1001,
    greetingMessage: "Diagnostic greeting.",
    failureMessage: "Diagnostic failure.",
    llm: buildLlmConfig("You are a test assistant. Say one short sentence."),
    tts: buildTtsConfig(voiceId),
    idleTimeout: 60,
  });
  const agentId = result.agent?.agent_id;
  console.log("OK: join returned agent_id:", agentId);
  if (agentId) {
    await stopSession({
      agentId,
      channel,
      agentUid: 1001,
    });
    console.log("OK: agent stopped");
  }
}

async function main() {
  console.log("Agora voice pipeline — component checks");
  console.log("Env snapshot (masked):");
  console.log("  AGORA_APP_ID:", mask(process.env.AGORA_APP_ID));
  console.log("  AGORA_APP_CERTIFICATE:", mask(process.env.AGORA_APP_CERTIFICATE));
  console.log("  MISTRAL_API_KEY:", mask(process.env.MISTRAL_API_KEY));
  console.log("  OPENAI_API_KEY:", mask(process.env.OPENAI_API_KEY));
  console.log("  ELEVENLABS_API_KEY:", mask(process.env.ELEVENLABS_API_KEY));
  console.log("  LLM_MODEL:", process.env.LLM_MODEL || "(default)");

  await step("1) Mistral (direct REST, non-stream)", testMistral);
  await step("2) OpenAI (direct REST, if key set)", testOpenAI);
  await step("3) ElevenLabs (user + butler voice_id)", testElevenLabs);
  await step("4) Agora token generation (RTC + ConvoAI)", () =>
    Promise.resolve(testAgoraTokens())
  );
  await step("5) Payload shape we send to /join", printPayloadShape);

  if (process.argv.includes("--live")) {
    await step("6) LIVE Agora join + leave (uses quota)", testLiveJoin);
  } else {
    console.log(
      "\nTip: run `npm run agora:diagnose -- --live` to test real Agora join/stop."
    );
  }

  console.log(
    "\n━━ Client reminder ━━\nHearing the agent requires joining the SAME channel with the SAME playerUid and the rtcToken from /interact (Web demo or app). This script does not test your speakers."
  );
}

main();

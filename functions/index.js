/**
 * Cloud Functions for Montagem USET.
 *
 * Sends push notifications (FCM) automatically when a pending item is created
 * or marked as awaiting validation, targeting topics the app subscribes to.
 */
const {onDocumentCreated, onDocumentUpdated} =
    require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

/**
 * Converts a name (team/producer, possibly with accents/spaces) into a valid
 * FCM topic. MUST stay identical to the Dart sanitizer in
 * lib/utils/fcm_topics.dart.
 * @param {string} prefix topic prefix ("team" | "producer")
 * @param {string} raw raw name
 * @return {string} sanitized topic
 */
function sanitize(prefix, raw) {
  let s = (raw || "").toLowerCase().trim();
  const accents = {
    "á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a",
    "é": "e", "ê": "e", "è": "e", "ë": "e",
    "í": "i", "ì": "i", "î": "i", "ï": "i",
    "ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
    "ú": "u", "ù": "u", "û": "u", "ü": "u",
    "ç": "c", "ñ": "n",
  };
  for (const [k, v] of Object.entries(accents)) {
    s = s.split(k).join(v);
  }
  s = s.replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
  return `${prefix}_${s}`;
}

/**
 * Sends one notification per topic, ignoring individual failures.
 * @param {string[]} topics list of FCM topics
 * @param {string} title notification title
 * @param {string} body notification body
 * @return {Promise} resolved when all sends settle
 */
function sendToTopics(topics, title, body) {
  const sends = topics.map((topic) =>
    getMessaging().send({
      topic,
      notification: {title, body},
      android: {priority: "high"},
    }));
  return Promise.allSettled(sends);
}

// New pending item → notify the assigned team and the producer.
exports.onPendingCreated = onDocumentCreated(
    "pending_items/{id}", async (event) => {
      const data = event.data && event.data.data();
      if (!data) return;

      const team = data.team || "";
      const producer = data.producerName || "";
      const client = data.clientName || "";
      const local = data.local || "";
      const desc = data.description || "";
      const fromClient = (data.origem || "equipe") === "cliente";

      const prefix = fromClient ? "Pedido do expositor" : "Nova pendência";
      const title = team ? `${prefix} — ${team}` : prefix;
      const where = local ? ` (Stand ${local})` : "";
      const body = `${client}${where}: ${desc}`;

      const topics = [];
      if (team) topics.push(sanitize("team", team));
      if (producer) topics.push(sanitize("producer", producer));
      // Exhibitor-submitted requests also alert admins, so they stay aware.
      if (fromClient) topics.push("admins");
      if (topics.length === 0) return;

      await sendToTopics(topics, title, body);
    });

// Producer marked item as done (awaiting validation) → notify admins.
exports.onPendingUpdated = onDocumentUpdated(
    "pending_items/{id}", async (event) => {
      const before = event.data && event.data.before.data();
      const after = event.data && event.data.after.data();
      if (!before || !after) return;

      const becameAwaiting =
          !before.awaitingValidation &&
          after.awaitingValidation === true &&
          after.isResolved !== true;
      if (!becameAwaiting) return;

      const client = after.clientName || "";
      const desc = after.description || "";
      const team = after.team ? `${after.team} — ` : "";
      await sendToTopics(
          ["admins"],
          "Pendência aguardando validação",
          `${team}${client}: ${desc}`);
    });

/**
 * Cloud Functions for Montagem USET.
 *
 * - onPendingCreated: notifica equipe + produtor quando pendência é criada
 * - onPendingUpdated: notifica admins quando pendência vai para validação
 * - dailyMontageReminder: às 18h BRT envia push aos produtores de feiras em
 *   modo produção que ainda não enviaram foto de montagem naquele dia
 */
const {onDocumentCreated, onDocumentUpdated} =
    require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {initializeApp} = require("firebase-admin/app");
const {getMessaging} = require("firebase-admin/messaging");
const {getFirestore} = require("firebase-admin/firestore");

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

// New client detected during sheet sync → notify producer + consultant.
exports.onNewClientSynced = onDocumentCreated(
    "sync_events/{id}", async (event) => {
      const data = event.data && event.data.data();
      if (!data) return;

      const producer = data.producerName || "";
      const consultant = data.consultantName || "";
      const client = data.clientName || "";
      const fair = data.fairName || "";

      const title = "Novo cliente na planilha";
      const body = fair
          ? `${client} foi adicionado à feira "${fair}".`
          : `${client} foi adicionado à planilha.`;

      const topics = [];
      if (producer) topics.push(sanitize("producer", producer));
      if (consultant) topics.push(sanitize("consultant", consultant));
      if (topics.length === 0) return;

      await sendToTopics(topics, title, body);

      // Delete the transient event document after processing.
      try {
        await event.data.ref.delete();
      } catch (_) {}
    });

// New client broadcast → notifies all users subscribed to the `new_clients` topic.
// Uses the clientId as the document ID (set by the app), so this onCreate trigger
// fires exactly once per unique client across all syncs.
exports.onNewClientBroadcast = onDocumentCreated(
    "new_client_broadcasts/{docId}", async (event) => {
      const data = event.data && event.data.data();
      if (!data) return;

      const client = data.clientName || "Novo cliente";
      const fair = data.fairName || "";
      const title = "Novo cliente na planilha";
      const body = fair
          ? `${client} foi adicionado à feira "${fair}".`
          : `${client} foi adicionado à planilha.`;

      await sendToTopics(["new_clients"], title, body);
    });

// New aviso published by admin → notifies selected target groups or users via FCM.
exports.onAvisoCreated = onDocumentCreated(
    "avisos/{docId}", async (event) => {
      const data = event.data && event.data.data();
      if (!data) return;

      const title = data.title || "Aviso";
      const body = data.body || "";

      const targetType = data.targetType || "groups";
      let topics = [];

      if (targetType === "users" && Array.isArray(data.targetUsers) && data.targetUsers.length > 0) {
        // Send to each user's individual FCM topic
        for (const user of data.targetUsers) {
          const name = user.name || "";
          const role = user.role || "";
          const team = user.team || "";
          if (!name || !role) continue;
          if (role === "producer") topics.push(sanitize("producer", name));
          else if (role === "consultant") topics.push(sanitize("consultant", name));
          else if (role === "analyst") topics.push(sanitize("analyst", name));
          else if (role === "leader") topics.push(sanitize("team", team || name));
          else if (role === "admin" || role === "manager") topics.push("admins");
        }
      } else {
        // existing group logic
        const groupToTopic = {
          todos: "new_clients",
          produtores: "group_produtores",
          consultores: "group_consultores",
          lideres: "group_lideres",
          analistas: "group_analistas",
          admins: "admins",
        };
        const groups = Array.isArray(data.targetGroups) && data.targetGroups.length > 0
            ? data.targetGroups
            : ["todos"];
        topics = [...new Set(groups.map((g) => groupToTopic[g]).filter(Boolean))];
      }

      topics = [...new Set(topics)];
      if (topics.length === 0) return;

      const notifTitle = `⚠️ ${title}`;
      const notifBody = body.length > 200
          ? body.substring(0, 197) + "..."
          : (body || "Nova mensagem da coordenação.");

      await sendToTopics(topics, notifTitle, notifBody);
    });

// New freight request → notify logistics team (group_logistica)
exports.onFreightRequestCreated = onDocumentCreated(
    "freight_requests/{id}", async (event) => {
      const data = event.data && event.data.data();
      if (!data) return;

      const fairName = data.fairName || "";
      const number = data.number || "";
      const priority = data.priority === "urgente" ? "🚨 URGENTE — " : "";
      const title = `${priority}Nova solicitação de frete #${number}`;
      const body = `${fairName}: ${data.items || ""}`.substring(0, 200);

      await sendToTopics(["group_logistica"], title, body);
    });

// Freight request status changed → notify requester OR logistics
exports.onFreightRequestUpdated = onDocumentUpdated(
    "freight_requests/{id}", async (event) => {
      const before = event.data && event.data.before.data();
      const after = event.data && event.data.after.data();
      if (!before || !after || before.status === after.status) return;

      const number = after.number || "";
      const fairName = after.fairName || "";
      const handledBy = after.handledBy || "Logística";

      if (after.status === "agendado") {
        const topic = after.requesterTopic || "";
        if (!topic) return;
        await sendToTopics(
            [topic],
            `Frete #${number} agendado ✅`,
            `${fairName} — ${handledBy} agendou seu frete.`);
      } else if (after.status === "despachado") {
        const topic = after.requesterTopic || "";
        if (!topic) return;
        await sendToTopics(
            [topic],
            `Frete #${number} despachado 🚚`,
            `${fairName} — ${handledBy} despachou seu frete. Confirme o recebimento.`);
      } else if (after.status === "finalizado") {
        await sendToTopics(
            ["group_logistica"],
            `Frete #${number} recebido ✔️`,
            `${fairName} — ${after.requestedBy || "Solicitante"} confirmou o recebimento.`);
      }
    });

// Daily 18:00 BRT reminder to producers who haven't sent a montage photo yet.
exports.dailyMontageReminder = onSchedule(
    {schedule: "0 18 * * *", timeZone: "America/Sao_Paulo"},
    async (_event) => {
      const firestore = getFirestore();

      // Find fairs currently in production mode.
      const fairsSnap = await firestore.collection("fairs").get();
      const productionFairs = fairsSnap.docs
          .filter((d) => d.data().mode === "producao")
          .map((d) => ({id: d.id, name: d.data().name || ""}));

      if (productionFairs.length === 0) return;

      // "Today" in BRT: Dart stores DateTime.now().toIso8601String() in local
      // time (BRT), so we compare the date portion after subtracting UTC-3.
      const nowUTC = new Date();
      const brtMs = nowUTC.getTime() - (3 * 60 * 60 * 1000);
      const brtDate = new Date(brtMs).toISOString().split("T")[0]; // "YYYY-MM-DD"

      for (const fair of productionFairs) {
        // Producers who already sent a photo today.
        const updatesSnap = await firestore.collection("montage_updates")
            .where("fairName", "==", fair.name)
            .get();

        const sentToday = new Set(
            updatesSnap.docs
                .filter((d) =>
                  (d.data().createdAt || "").startsWith(brtDate))
                .map((d) => d.data().createdBy || "")
                .filter(Boolean),
        );

        // All producers involved in this fair (from pending_items).
        const pendingSnap = await firestore.collection("pending_items")
            .where("fairName", "==", fair.name)
            .get();

        const allProducers = new Set(
            pendingSnap.docs
                .map((d) => d.data().producerName || "")
                .filter(Boolean),
        );

        // Notify those who haven't sent today.
        const toNotify = [...allProducers].filter((p) => !sentToday.has(p));
        if (toNotify.length === 0) continue;

        await Promise.allSettled(
            toNotify.map((producer) =>
              sendToTopics(
                  [sanitize("producer", producer)],
                  "Hora de atualizar a montagem! 📸",
                  `Envie a foto de progresso dos seus stands — ${fair.name}`,
              ),
            ),
        );
      }
    });

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
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {initializeApp} = require("firebase-admin/app");
const {getMessaging} = require("firebase-admin/messaging");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {randomBytes} = require("crypto");

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
function sendToTopics(topics, title, body, data) {
  // O payload `data` é o que permite ao app abrir a tela certa ao tocar na
  // notificação. Sem ele o toque apenas abria o app na tela inicial.
  // Todos os valores precisam ser string.
  const payload = {};
  if (data) {
    for (const [k, v] of Object.entries(data)) {
      if (v !== undefined && v !== null && v !== "") payload[k] = String(v);
    }
  }
  const sends = topics.map((topic) =>
    getMessaging().send({
      topic,
      notification: {title, body},
      data: payload,
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

      const fair = data.fairName || "";
      const prefix = fromClient ? "Pedido do expositor" : "Nova pendência";
      const title = team ? `${prefix} — ${team}` : prefix;
      const where = local ? ` (Stand ${local})` : "";
      // A feira vai no corpo: quem administra várias recebe aviso de todas,
      // mas o quadro mostra só a feira aberta — sem isso não dá para saber
      // onde procurar.
      const body = `${fair ? `[${fair}] ` : ""}${client}${where}: ${desc}`;

      // Só os envolvidos são notificados. Antes ia para o tópico da equipe
      // inteira, então todo líder daquela equipe recebia pendências de
      // clientes que não são dele.
      const consultant = data.consultantName || "";
      const responsible = data.responsible || "";
      const approval = data.approvalStatus || "none";

      // Pedido da organizadora aguardando aprovação: só quem aprova é avisado.
      // Liberar para campo aqui mostraria a pendência antes da aprovação.
      if (approval === "pendente") {
        await sendToTopics(
            ["admins"].concat(consultant ? [sanitize("consultant", consultant)] : []),
            "Pedido aguardando aprovação",
            `${fair ? `[${fair}] ` : ""}${client}${where}: ${desc}`,
            {
              type: "pending",
              clientId: data.clientId || "",
              pendingId: event.params.id,
              fairName: data.fairName || "",
            });
        return;
      }

      const topics = ["admins", "group_analistas"];
      if (producer) topics.push(sanitize("producer", producer));
      if (consultant) topics.push(sanitize("consultant", consultant));
      // Líder: pelo nome do responsável daquele cliente/equipe. Sem
      // responsável definido, cai no tópico da equipe para ninguém ficar sem
      // saber do serviço.
      if (responsible) topics.push(sanitize("leader", responsible));
      else if (team) topics.push(sanitize("team", team));

      await sendToTopics(topics, title, body, {
        type: "pending",
        clientId: data.clientId || "",
        pendingId: event.params.id,
        fairName: data.fairName || "",
      });
    });

// Producer marked item as done (awaiting validation) → notify admins.
exports.onPendingUpdated = onDocumentUpdated(
    "pending_items/{id}", async (event) => {
      const before = event.data && event.data.before.data();
      const after = event.data && event.data.after.data();
      if (!before || !after) return;

      const client = after.clientName || "";
      const desc = after.description || "";
      const teamLabel = after.team ? `${after.team} — ` : "";
      const producer = after.producerName || "";
      const consultant = after.consultantName || "";
      const responsible = after.responsible || "";
      const payload = {
        type: "pending",
        clientId: after.clientId || "",
        pendingId: event.params.id,
        fairName: after.fairName || "",
      };

      /** Envolvidos no chamado: produtor e consultor do cliente, o líder
       * responsável, mais admin/gerente e analistas.
       * @return {string[]} tópicos
       */
      function involved() {
        const t = ["admins", "group_analistas"];
        if (producer) t.push(sanitize("producer", producer));
        if (consultant) t.push(sanitize("consultant", consultant));
        if (responsible) t.push(sanitize("leader", responsible));
        else if (after.team) t.push(sanitize("team", after.team));
        return t;
      }

      // Produtor concluiu → aguardando validação do admin.
      if (!before.awaitingValidation &&
          after.awaitingValidation === true &&
          after.isResolved !== true) {
        const fair = after.fairName || "";
        await sendToTopics(
            ["admins"],
            "Pendência aguardando validação",
            `${fair ? `[${fair}] ` : ""}${teamLabel}${client}: ${desc}`,
            payload);
        return;
      }

      // Pedido da organizadora foi aprovado → agora libera para o campo.
      if (before.approvalStatus === "pendente" &&
          after.approvalStatus === "aprovada") {
        await sendToTopics(
            involved(),
            "Pedido aprovado",
            `${teamLabel}${client}: ${desc}`,
            payload);
        return;
      }

      // Chamado concluído.
      if (before.isResolved !== true && after.isResolved === true) {
        const rejected = after.approvalStatus === "recusada";
        await sendToTopics(
            involved(),
            rejected ? "Chamado recusado" : "Pendência concluída",
            `${teamLabel}${client}: ${desc}`,
            payload);
      }
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

      await sendToTopics(topics, title, body, {
        type: "client",
        clientId: data.clientId || "",
        fairName: fair,
      });

      // O documento FICA. O id dele é determinado pelo conteúdo e a função só
      // dispara na criação, então mantê-lo é o que impede a mesma atribuição
      // de ser notificada de novo por cada aparelho que sincronizar. A
      // limpeza diária remove os antigos.
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

const GROUP_TOPICS = {
  todos: "new_clients",
  produtores: "group_produtores",
  consultores: "group_consultores",
  lideres: "group_lideres",
  analistas: "group_analistas",
  admins: "admins",
  logistica: "group_logistica",
};

/** Tópicos para falar com UMA pessoa.
 *
 * O líder ia para o tópico da equipe: um aviso dirigido a um líder chegava a
 * todos os líderes daquela equipe. O gerente ia para "admins", o que
 * espalhava para toda a administração. Os dois agora têm tópico por nome.
 *
 * @param {object} user {name, role, team}
 * @return {string[]} tópicos
 */
function userTopics(user) {
  const name = (user && user.name) || "";
  const role = (user && user.role) || "";
  if (!name || !role) return [];
  switch (role) {
    case "producer": return [sanitize("producer", name)];
    case "consultant": return [sanitize("consultant", name)];
    case "analyst": return [sanitize("analyst", name)];
    case "leader": return [sanitize("leader", name)];
    case "logistica": return [sanitize("logistica", name)];
    case "manager": return [sanitize("manager", name)];
    // Admin não tem tópico por nome: todos compartilham "admins".
    case "admin": return ["admins"];
    default: return [];
  }
}

// New aviso published by admin → notifies selected target groups or users via FCM.
exports.onAvisoCreated = onDocumentCreated(
    "avisos/{docId}", async (event) => {
      const data = event.data && event.data.data();
      if (!data) return;

      const title = data.title || "Aviso";
      const body = data.body || "";

      // Grupos e pessoas se SOMAM. Antes era um ou outro: o aviso por feira
      // precisa das duas coisas — as pessoas daquela feira mais os papéis que
      // entram sempre.
      const targetType = data.targetType || "groups";
      const users = Array.isArray(data.targetUsers) ? data.targetUsers : [];
      const groups = Array.isArray(data.targetGroups) ? data.targetGroups : [];
      let topics = [];

      for (const user of users) {
        topics.push(...userTopics(user));
      }

      // Sem nenhum alvo definido o aviso é geral — mas só quando o envio não
      // era dirigido. Um aviso por pessoa ou por feira que perdeu a lista não
      // pode virar aviso para todo mundo.
      const dirigido = targetType === "users" || targetType === "fair";
      const gruposFinais =
          groups.length > 0 ? groups : (dirigido ? [] : ["todos"]);
      topics.push(...gruposFinais.map((g) => GROUP_TOPICS[g]).filter(Boolean));

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

// ─── Autenticação de PIN no servidor ────────────────────────────────────────
//
// Hoje o app lê a coleção de PINs direto do Firestore para montar a lista de
// nomes e para conferir o código digitado. Como a regra atual libera leitura a
// qualquer sessão autenticada — e o app faz login anônimo, inclusive nos
// portais públicos —, os PINs de todos os papéis ficam legíveis por quem abrir
// o link.
//
// Estas duas funções movem isso para o servidor. Enquanto as regras não forem
// fechadas elas convivem com o acesso direto; depois passam a ser o único
// caminho, e o cliente deixa de ver PIN algum.

/** Coleções por papel. Cada uma guarda o PIN num campo `pin`.
 * `byField` marca as que identificam o usuário por um campo `name` em vez do
 * id do documento.
 */
const PIN_SOURCES = {
  producer: {collection: "producer_pins"},
  consultant: {collection: "consultant_pins"},
  manager: {collection: "manager_pins"},
  leader: {collection: "team_leader_pins", extra: ["team"]},
  analyst: {collection: "analyst_pins"},
  // fairIds é a lista de feiras da organizadora; fairId é o campo antigo, de
  // uma feira só, mantido para os aparelhos que ainda não atualizaram.
  organizer: {collection: "organizer_pins", extra: ["fairId", "fairIds"]},
  admin: {collection: "admin_users", byField: true},
  logistica: {collection: "logistics_users", byField: true},
};

/** Normaliza o nome para o formato de id usado nas coleções por documento.
 * @param {string} name nome do usuário
 * @return {string} chave do documento
 */
function userKey(name) {
  return String(name || "").toLowerCase().trim()
      .replace(/ /g, "_").replace(/[^a-z0-9_]/g, "");
}

/** Lista os nomes de um papel, sem devolver PIN nenhum.
 * Substitui as chamadas get*WithPins() do app, que hoje trazem o PIN junto
 * só para exibir a lista.
 */
exports.listUsers = onCall(async (request) => {
  const role = request.data && request.data.role;
  const source = PIN_SOURCES[role];
  if (!source) throw new HttpsError("invalid-argument", "papel inválido");

  const snap = await getFirestore().collection(source.collection).get();
  const users = snap.docs.map((d) => {
    const data = d.data() || {};
    const entry = {name: source.byField ? (data.name || "") : d.id};
    for (const f of source.extra || []) entry[f] = data[f] ?? null;
    return entry;
  }).filter((u) => u.name);

  users.sort((a, b) => a.name.localeCompare(b.name));
  return {users};
});

/** Confere o PIN no servidor. O código digitado sobe; o cadastrado nunca desce.
 * Devolve também os campos auxiliares do papel (a equipe do líder, a feira da
 * organizadora), que o app precisa logo após entrar.
 */
exports.verifyPin = onCall(async (request) => {
  const {role, name, pin} = request.data || {};
  const source = PIN_SOURCES[role];
  if (!source || !name) {
    throw new HttpsError("invalid-argument", "papel ou nome ausente");
  }
  const target = `${role}|${name}`;
  await checkAttempts(request, target);

  let data = null;
  if (source.byField) {
    const snap = await getFirestore().collection(source.collection)
        .where("name", "==", name).limit(1).get();
    if (!snap.empty) data = snap.docs[0].data();
  } else {
    // As coleções por documento usam o nome como id; admin_users e
    // logistics_users usam a chave normalizada.
    const doc = await getFirestore().collection(source.collection)
        .doc(name).get();
    if (doc.exists) data = doc.data();
    if (!data) {
      const alt = await getFirestore().collection(source.collection)
          .doc(userKey(name)).get();
      if (alt.exists) data = alt.data();
    }
  }

  if (!data || !data.pin) return {ok: false, reason: "nao_cadastrado"};
  if (String(data.pin) !== String(pin || "")) {
    await recordAttempt(request, target, false);
    return {ok: false, reason: "pin_incorreto"};
  }
  await recordAttempt(request, target, true);

  const out = {ok: true};
  for (const f of source.extra || []) out[f] = data[f] ?? null;
  // Quem entra como admin já sai com a sessão de gestão pronta, para não
  // pedir o PIN de novo ao abrir Configurações.
  if (role === "admin") out.token = await mintAdminSession(name);
  return out;
});

// ─── Sessão de administrador ────────────────────────────────────────────────
//
// Sem isto a tela de gestão precisaria escrever direto nas coleções de PIN, e
// aí as regras do Firestore teriam de continuar abertas para qualquer sessão
// autenticada — o buraco que estamos fechando. O app guarda só o token; o
// servidor é quem sabe a quem ele pertence e até quando vale.

const ADMIN_SESSION_TTL_MS = 12 * 60 * 60 * 1000;

// ─── Freio de tentativas ────────────────────────────────────────────────────
//
// Com o PIN saindo do cliente, a única forma de descobri-lo passa a ser
// tentar. São seis dígitos: sem freio, um script varre o espaço inteiro em
// poucas horas. O contador é por origem e some sozinho ao fim da janela.

const ATTEMPT_WINDOW_MS = 15 * 60 * 1000;
const ATTEMPT_LIMIT = 12;

/** Identificador da tentativa.
 *
 * A chave inclui o alvo (papel + nome), não só a origem: num pavilhão a
 * equipe inteira sai pelo mesmo IP, e contar só por IP faria o erro de um
 * trancar o login de todos. Assim o freio vale por conta, que é o que a
 * força bruta precisa atacar.
 *
 * @param {object} request requisição da callable
 * @param {string} target papel|nome sendo tentado ("" no portão de admin)
 * @return {string} chave do contador
 */
function callerKey(request, target) {
  const raw = request.rawRequest || {};
  const ip = (raw.headers && raw.headers["x-forwarded-for"]) || raw.ip || "";
  const first = String(ip).split(",")[0].trim();
  const uid = (request.auth && request.auth.uid) || "";
  const origin = first || uid || "desconhecido";
  return `${origin}|${target || ""}`
      .replace(/[^a-zA-Z0-9.:|_-]/g, "_").slice(0, 200);
}

/** Recusa quando a origem já errou demais na janela.
 * @param {object} request requisição da callable
 * @param {string} target papel|nome sendo tentado
 */
async function checkAttempts(request, target) {
  const ref = getFirestore().collection("pin_attempts")
      .doc(callerKey(request, target));
  const doc = await ref.get();
  const data = doc.exists ? doc.data() : null;
  if (!data || (data.windowStart || 0) + ATTEMPT_WINDOW_MS < Date.now()) return;
  if ((data.fails || 0) >= ATTEMPT_LIMIT) {
    throw new HttpsError("resource-exhausted", "muitas_tentativas");
  }
}

/** Registra o resultado da tentativa: erro soma, acerto zera.
 * @param {object} request requisição da callable
 * @param {string} target papel|nome sendo tentado
 * @param {boolean} ok se o PIN conferiu
 */
async function recordAttempt(request, target, ok) {
  const ref = getFirestore().collection("pin_attempts")
      .doc(callerKey(request, target));
  if (ok) {
    await ref.delete().catch(() => {});
    return;
  }
  const now = Date.now();
  await getFirestore().runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const data = doc.exists ? doc.data() : null;
    const fresh = !data || (data.windowStart || 0) + ATTEMPT_WINDOW_MS < now;
    tx.set(ref, {
      windowStart: fresh ? now : data.windowStart,
      fails: fresh ? 1 : (data.fails || 0) + 1,
    });
  }).catch(() => {
    // Não deixar o freio derrubar o login de quem digitou certo.
  });
}

/** Cria uma sessão de administrador e devolve o token.
 * @param {string} name nome do administrador
 * @return {Promise<string>} token da sessão
 */
async function mintAdminSession(name) {
  const token = randomBytes(32).toString("hex");
  const now = Date.now();
  await getFirestore().collection("admin_sessions").doc(token).set({
    name: String(name || ""),
    createdAt: now,
    expiresAt: now + ADMIN_SESSION_TTL_MS,
  });
  return token;
}

/** Valida o token e devolve o nome do administrador. Lança se inválido.
 * @param {string} token token recebido do app
 * @return {Promise<string>} nome do administrador
 */
async function requireAdminSession(token) {
  if (!token) throw new HttpsError("unauthenticated", "sessao_ausente");
  const doc = await getFirestore().collection("admin_sessions")
      .doc(String(token)).get();
  if (!doc.exists) throw new HttpsError("permission-denied", "sessao_invalida");
  const data = doc.data() || {};
  if (!data.expiresAt || data.expiresAt < Date.now()) {
    await doc.ref.delete().catch(() => {});
    throw new HttpsError("permission-denied", "sessao_expirada");
  }
  return data.name || "";
}

/** Portão de administrador por PIN, sem escolher nome.
 *
 * Substitui a comparação que era feita no aparelho contra um PIN padrão
 * embutido no código — qualquer um que abrisse o APK tinha acesso de admin.
 * Aqui o PIN digitado é conferido contra os administradores cadastrados e o
 * app recebe apenas um token de sessão.
 */
exports.adminGate = onCall(async (request) => {
  const pin = String((request.data && request.data.pin) || "");
  if (!pin) throw new HttpsError("invalid-argument", "pin ausente");
  await checkAttempts(request, "admin|gate");

  const snap = await getFirestore().collection("admin_users").get();
  if (snap.empty) return {ok: false, reason: "nenhum_admin"};

  const match = snap.docs.find((d) => String((d.data() || {}).pin) === pin);
  if (!match) {
    await recordAttempt(request, "admin|gate", false);
    return {ok: false, reason: "pin_incorreto"};
  }
  await recordAttempt(request, "admin|gate", true);

  const name = (match.data() || {}).name || match.id;
  return {ok: true, name, token: await mintAdminSession(name)};
});

/** Encerra a sessão de gestão (logout do admin). */
exports.adminLogout = onCall(async (request) => {
  const token = (request.data && request.data.token) || "";
  if (token) {
    await getFirestore().collection("admin_sessions").doc(String(token))
        .delete().catch(() => {});
  }
  return {ok: true};
});

/** Limpa sessões vencidas. Sem isso a coleção só cresce. */
exports.cleanupAdminSessions = onSchedule(
    {schedule: "0 4 * * *", timeZone: "America/Sao_Paulo"},
    async () => {
      const db = getFirestore();
      const batch = db.batch();

      const sessions = await db.collection("admin_sessions")
          .where("expiresAt", "<", Date.now()).limit(400).get();
      sessions.docs.forEach((d) => batch.delete(d.ref));

      // Contadores de tentativa também: a janela é de 15 minutos, então
      // qualquer registro do dia anterior já não vale mais nada.
      const attempts = await db.collection("pin_attempts")
          .where("windowStart", "<", Date.now() - ATTEMPT_WINDOW_MS)
          .limit(400).get();
      attempts.docs.forEach((d) => batch.delete(d.ref));

      if (sessions.size + attempts.size > 0) await batch.commit();
      console.log(
          `limpeza: ${sessions.size} sessões, ${attempts.size} tentativas`);
    });

// ─── Gestão de usuários e PINs ──────────────────────────────────────────────

/** Id do documento para o papel indicado.
 * @param {object} source entrada de PIN_SOURCES
 * @param {string} name nome do usuário
 * @return {string} id do documento
 */
function docIdFor(source, name) {
  // admin_users e logistics_users guardam o nome num campo e usam a chave
  // normalizada como id; as demais usam o próprio nome como id.
  return source.byField ? userKey(name) : name;
}

/** Gestão dos usuários e PINs, restrita a quem tem sessão de admin.
 *
 * Uma função só com várias operações: a tela de Configurações mexe em oito
 * coleções e trinta chamadas separadas seriam trinta pontos para manter em pé.
 *
 * Operações:
 *  - list   {role}                       → [{name, pin, ...extra}]
 *  - set    {role, name, pin, extra}     → grava (merge nos campos auxiliares)
 *  - delete {role, name}                 → remove
 */
exports.manageUsers = onCall(async (request) => {
  const {token, op, role, name, pin, extra} = request.data || {};
  await requireAdminSession(token);

  const source = PIN_SOURCES[role];
  if (!source) throw new HttpsError("invalid-argument", "papel inválido");
  const col = getFirestore().collection(source.collection);

  if (op === "list") {
    const snap = await col.get();
    const users = snap.docs.map((d) => {
      const data = d.data() || {};
      const entry = {
        name: source.byField ? (data.name || "") : d.id,
        pin: data.pin != null ? String(data.pin) : null,
      };
      for (const f of source.extra || []) entry[f] = data[f] ?? null;
      return entry;
    }).filter((u) => u.name);
    users.sort((a, b) => a.name.localeCompare(b.name));
    return {users};
  }

  if (!name) throw new HttpsError("invalid-argument", "nome ausente");
  const ref = col.doc(docIdFor(source, name));

  if (op === "delete") {
    await ref.delete();
    return {ok: true};
  }

  if (op === "set") {
    const payload = {};
    if (source.byField) payload.name = name;
    if (pin != null) payload.pin = String(pin);
    for (const f of source.extra || []) {
      if (!extra || !(f in extra)) continue;
      // null explícito apaga o campo. Sem isto não haveria como desfazer um
      // vínculo — o merge preservaria o valor antigo para sempre.
      payload[f] = extra[f] === null ? FieldValue.delete() : extra[f];
    }
    // merge para não apagar a equipe do líder ao trocar só o PIN, nem o
    // contrário.
    await ref.set(payload, {merge: true});
    return {ok: true};
  }

  throw new HttpsError("invalid-argument", "operação inválida");
});

// ─── Reuniões ───────────────────────────────────────────────────────────────
//
// Uma reunião é sempre de uma feira. Quem convida escolhe os participantes; o
// app manda a lista já resolvida porque só ele sabe quem trabalha em cada
// feira — os clientes vivem no SQLite de cada aparelho, não no Firestore.

/** Texto de data e hora no fuso de São Paulo.
 * @param {string} iso data em ISO
 * @return {string} "31/07 às 14:30"
 */
function meetingWhen(iso) {
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "";
  const f = new Intl.DateTimeFormat("pt-BR", {
    timeZone: "America/Sao_Paulo",
    day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit",
  }).formatToParts(d);
  const p = {};
  for (const {type, value} of f) p[type] = value;
  return `${p.day}/${p.month} às ${p.hour}:${p.minute}`;
}

/** Tópicos de todos os participantes de uma reunião.
 * @param {object} data documento da reunião
 * @return {string[]} tópicos sem repetição
 */
function meetingTopics(data) {
  const list = Array.isArray(data.participants) ? data.participants : [];
  const topics = [];
  for (const p of list) topics.push(...userTopics(p));
  return [...new Set(topics)];
}

// Reunião agendada → avisa os participantes.
exports.onMeetingCreated = onDocumentCreated(
    "meetings/{id}", async (event) => {
      const data = event.data && event.data.data();
      if (!data || data.canceled === true) return;

      const topics = meetingTopics(data);
      if (topics.length === 0) return;

      const fair = data.fairName || "";
      const local = data.location || "";
      const quando = meetingWhen(data.startsAt || "");

      await sendToTopics(
          topics,
          `📅 Reunião — ${data.title || "sem título"}`,
          `${fair ? `[${fair}] ` : ""}${quando}` +
            `${local ? ` · ${local}` : ""}`,
          {
            type: "meeting",
            meetingId: event.params.id,
            fairName: fair,
          });
    });

// Reunião cancelada → avisa quem tinha sido convidado.
exports.onMeetingUpdated = onDocumentUpdated(
    "meetings/{id}", async (event) => {
      const before = event.data && event.data.before.data();
      const after = event.data && event.data.after.data();
      if (!before || !after) return;
      if (before.canceled === true || after.canceled !== true) return;

      const topics = meetingTopics(after);
      if (topics.length === 0) return;

      await sendToTopics(
          topics,
          `❌ Reunião cancelada — ${after.title || ""}`,
          `${after.fairName ? `[${after.fairName}] ` : ""}` +
            `${meetingWhen(after.startsAt || "")}`,
          {type: "meeting", meetingId: event.params.id});
    });

// Lembrete 30 minutos antes.
//
// Roda a cada 5 minutos e pega tudo o que começa nos próximos 30. A marca
// reminderSent é gravada ANTES do envio: repetir o lembrete incomoda mais do
// que perder um, e sem a marca uma falha no meio do envio faria a próxima
// rodada avisar todo mundo de novo.
exports.meetingReminders = onSchedule(
    {schedule: "*/5 * * * *", timeZone: "America/Sao_Paulo"},
    async () => {
      const agora = Date.now();
      const limite = new Date(agora + 30 * 60 * 1000).toISOString();
      const passado = new Date(agora - 5 * 60 * 1000).toISOString();

      const snap = await getFirestore().collection("meetings")
          .where("startsAt", "<=", limite)
          .where("startsAt", ">=", passado)
          .limit(50)
          .get();

      let enviados = 0;
      for (const doc of snap.docs) {
        const data = doc.data() || {};
        if (data.reminderSent === true || data.canceled === true) continue;

        await doc.ref.set({reminderSent: true}, {merge: true});

        const topics = meetingTopics(data);
        if (topics.length === 0) continue;

        const local = data.location || "";
        await sendToTopics(
            topics,
            `⏰ Reunião em 30 minutos — ${data.title || ""}`,
            `${data.fairName ? `[${data.fairName}] ` : ""}` +
              `${meetingWhen(data.startsAt || "")}` +
              `${local ? ` · ${local}` : ""}`,
            {type: "meeting", meetingId: doc.id, fairName: data.fairName || ""});
        enviados++;
      }
      if (enviados > 0) console.log(`lembretes de reunião: ${enviados}`);
    });

// ─── Versão mínima do app ───────────────────────────────────────────────────
//
// O número é lido por todos e escrito só por aqui. Se a escrita fosse direta,
// qualquer sessão autenticada — inclusive a anônima dos portais públicos —
// poderia exigir uma versão que não existe e trancar a equipe inteira fora do
// app no meio de uma montagem.
exports.setMinBuild = onCall(async (request) => {
  const {token, minBuild, message} = request.data || {};
  const quem = await requireAdminSession(token);

  const n = Number(minBuild);
  if (!Number.isInteger(n) || n < 0) {
    throw new HttpsError("invalid-argument", "build inválida");
  }

  await getFirestore().collection("app_config").doc("version").set({
    minBuild: n,
    message: String(message || ""),
    updatedAt: new Date().toISOString(),
    updatedBy: quem,
  }, {merge: true});

  return {ok: true};
});

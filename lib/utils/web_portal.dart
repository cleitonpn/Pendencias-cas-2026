/// Qual portal web a pessoa usou por último.
///
/// Um F5 numa URL sem fragmento (`/` puro) não diz de onde a pessoa veio, e o
/// roteador precisa decidir para onde mandar. Antes ele só conhecia a sessão
/// da organizadora, então quem estava no portal da equipe caía lá.
///
/// Fica num arquivo próprio para o roteador e as telas não se importarem
/// mutuamente.
const kLastWebPortal = 'web_last_portal';
const kPortalOrganizadora = 'organizadora';
const kPortalEquipe = 'equipe';

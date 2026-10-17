import '../models/question.dart';
import 'predefined_questions.dart';

const customQuestionAnswerHint =
    'Tómate tu tiempo. Cuéntale lo que recuerdes y cualquier detalle que te venga a la memoria.';

const predefinedQuestionAnswerHints = <String, String>{
  'childhood_home': 'Cuéntale dónde estaba, cómo eran las habitaciones, quién vivía contigo y qué recuerdos guardas de ella.',
  'earliest_memory': 'Cuéntale qué imagen te viene primero, dónde estabas, quién estaba cerca y qué sentías en aquel momento.',
  'childhood_personality': 'Cuéntale qué te ilusionaba, qué travesuras hacías y cómo te describían quienes te conocían de pequeño/a.',
  'childhood_games': 'Cuéntale las reglas de tu juego favorito, con quién jugabas y en qué rincón pasabais las tardes.',
  'school': 'Cuéntale cómo era el camino al colegio, qué profesor recuerdas y qué ocurría en el recreo.',
  'parents': 'Cuéntale cómo hablaban tus padres, qué costumbres tenían y algún gesto suyo que todavía te acompañe.',
  'grandparents': 'Cuéntale una visita a casa de tus abuelos, las historias que contaban o algo que aprendiste a su lado.',
  'siblings': 'Cuéntale qué compartías con tus hermanos, por qué discutíais y qué aventuras os unían.',
  'family_tradition': 'Cuéntale cuándo os reuníais, quién preparaba cada cosa y qué hacía especial esa tradición para ti.',
  'eighteen': 'Cuéntale cómo era un día tuyo a los 18, quiénes eran tus amigos y qué esperabas del futuro.',
  'youth_leisure': 'Cuéntale adónde salías, qué música sonaba y alguna anécdota de aquellos planes con amigos.',
  'first_job': 'Cuéntale cómo conseguiste ese trabajo, qué hacías y qué recuerdas de tu primer día o de tu primer sueldo.',
  'youth_dreams': 'Cuéntale qué te imaginabas haciendo de mayor, de dónde nació ese sueño y cómo fue cambiando con los años.',
  'meeting_partner': 'Cuéntale dónde os encontrasteis, quién dio el primer paso y qué te llamó la atención de esa persona.',
  'first_date': 'Cuéntale qué plan hicisteis, cómo te preparaste y qué detalle de aquella cita te sigue haciendo sonreír.',
  'wedding': 'Cuéntale quién estuvo contigo, cómo viviste los preparativos y qué momento de ese día querrías volver a vivir.',
  'happiest_moment': 'Cuéntale qué ocurrió, con quién compartiste esa alegría y por qué aquel instante fue tan importante para ti.',
  'important_decision': 'Cuéntale qué opciones tenías, qué te ayudó a decidir y cómo cambió tu vida después.',
  'cherished_period': 'Cuéntale dónde vivías entonces, qué personas formaban parte de tus días y qué echas de menos de esa etapa.',
  'advice_twenty': 'Cuéntale qué te preocupaba a los 20, qué has aprendido desde entonces y qué te habría gustado saber antes.',
  'family_legacy': 'Cuéntale qué valores has intentado transmitir y qué pequeños gestos o recuerdos te gustaría dejar en tu familia.',
};

String answerHintFor(Question question) =>
    predefinedQuestionAnswerHints[question.id] ?? customQuestionAnswerHint;

// Legacy requests transport only question_text. Resolve exact catalog entries
// once at the boundary; hints themselves are keyed by stable IDs, never fuzzy
// text matches. A custom request identical to a catalog entry is indistinguishable
// without changing the backend contract, which this feature deliberately avoids.
Question questionForReceivedRequest(String text) {
  for (final category in predefinedQuestionCategories) {
    for (final question in category.questions) {
      if (question.text == text) return question;
    }
  }
  return Question(text);
}

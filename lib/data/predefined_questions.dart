import '../models/question.dart';

const predefinedQuestionCategories = [
  QuestionCategory(
    name: 'Infancia',
    description: 'Recuerdos de cuando eras pequeño/a',
    questions: [
      Question(
        '¿Cómo era tu casa cuando eras pequeño/a?',
        id: 'childhood_home',
      ),
      Question(
        '¿Cuál es uno de tus primeros recuerdos?',
        id: 'earliest_memory',
      ),
      Question('¿Cómo eras de pequeño/a?', id: 'childhood_personality'),
      Question('¿A qué jugabas cuando eras niño/a?', id: 'childhood_games'),
      Question('¿Cómo era el colegio al que ibas?', id: 'school'),
    ],
  ),
  QuestionCategory(
    name: 'Familia',
    description: 'Padres, abuelos, hermanos y tradiciones',
    questions: [
      Question('¿Cómo eran tus padres?', id: 'parents'),
      Question('¿Qué recuerdas de tus abuelos?', id: 'grandparents'),
      Question('¿Cómo era la relación con tus hermanos?', id: 'siblings'),
      Question(
        '¿Qué tradición familiar recuerdas con más cariño?',
        id: 'family_tradition',
      ),
    ],
  ),
  QuestionCategory(
    name: 'Juventud',
    description: 'Amigos, sueños, estudios y primeros trabajos',
    questions: [
      Question('¿Cómo eras cuando tenías 18 años?', id: 'eighteen'),
      Question('¿Qué hacías para divertirte?', id: 'youth_leisure'),
      Question('¿Cuál fue tu primer trabajo?', id: 'first_job'),
      Question('¿Qué soñabas hacer cuando eras joven?', id: 'youth_dreams'),
    ],
  ),
  QuestionCategory(
    name: 'Amor y relaciones',
    description: 'Pareja, primeras citas y momentos juntos',
    questions: [
      Question('¿Cómo conociste a tu pareja?', id: 'meeting_partner'),
      Question('¿Cómo fue vuestra primera cita?', id: 'first_date'),
      Question('¿Qué recuerdas del día de tu boda?', id: 'wedding'),
    ],
  ),
  QuestionCategory(
    name: 'Vida',
    description: 'Decisiones, momentos importantes y aprendizajes',
    questions: [
      Question(
        '¿Cuál ha sido uno de los momentos más felices de tu vida?',
        id: 'happiest_moment',
      ),
      Question(
        '¿Cuál ha sido una de las decisiones más importantes que has tomado?',
        id: 'important_decision',
      ),
      Question(
        '¿Qué época de tu vida recuerdas con más cariño?',
        id: 'cherished_period',
      ),
      Question(
        '¿Qué consejo le darías a tu yo de 20 años?',
        id: 'advice_twenty',
      ),
      Question(
        '¿Qué te gustaría que tu familia recordara siempre de ti?',
        id: 'family_legacy',
      ),
    ],
  ),
];

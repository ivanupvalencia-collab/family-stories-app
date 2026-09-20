import '../models/question.dart';

const predefinedQuestionCategories = [
  QuestionCategory(
    name: 'Infancia',
    description: 'Recuerdos de cuando eras pequeño/a',
    questions: [
      Question('¿Cómo era tu casa cuando eras pequeño/a?'),
      Question('¿Cuál es uno de tus primeros recuerdos?'),
      Question('¿Cómo eras de pequeño/a?'),
      Question('¿A qué jugabas cuando eras niño/a?'),
      Question('¿Cómo era el colegio al que ibas?'),
    ],
  ),
  QuestionCategory(
    name: 'Familia',
    description: 'Padres, abuelos, hermanos y tradiciones',
    questions: [
      Question('¿Cómo eran tus padres?'),
      Question('¿Qué recuerdas de tus abuelos?'),
      Question('¿Cómo era la relación con tus hermanos?'),
      Question('¿Qué tradición familiar recuerdas con más cariño?'),
    ],
  ),
  QuestionCategory(
    name: 'Juventud',
    description: 'Amigos, sueños, estudios y primeros trabajos',
    questions: [
      Question('¿Cómo eras cuando tenías 18 años?'),
      Question('¿Qué hacías para divertirte?'),
      Question('¿Cuál fue tu primer trabajo?'),
      Question('¿Qué soñabas hacer cuando eras joven?'),
    ],
  ),
  QuestionCategory(
    name: 'Amor y relaciones',
    description: 'Pareja, primeras citas y momentos juntos',
    questions: [
      Question('¿Cómo conociste a tu pareja?'),
      Question('¿Cómo fue vuestra primera cita?'),
      Question('¿Qué recuerdas del día de tu boda?'),
    ],
  ),
  QuestionCategory(
    name: 'Vida',
    description: 'Decisiones, momentos importantes y aprendizajes',
    questions: [
      Question('¿Cuál ha sido uno de los momentos más felices de tu vida?'),
      Question(
        '¿Cuál ha sido una de las decisiones más importantes que has tomado?',
      ),
      Question('¿Qué época de tu vida recuerdas con más cariño?'),
      Question('¿Qué consejo le darías a tu yo de 20 años?'),
      Question('¿Qué te gustaría que tu familia recordara siempre de ti?'),
    ],
  ),
];

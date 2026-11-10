import 'dart:convert';
import '../builder/values.dart';
import 'model.dart';
import 'quiz.dart';
import 'crypto.dart';
import 'tasks.dart';
import 'library.dart';
import 'feedback.dart';
import 'requests.dart';
import 'registration.dart';

abstract final class BotTemplates {
  static const all = <BotTemplate>[
    BotTemplate(
      id: 'quiz',
      name: 'Quiz with scores',
      summary: 'Topics, multiple-choice questions and personal best scores.',
      description:
          'Choose a topic, answer questions, read explanations and keep a personal best for each topic. Repeated answers cannot award extra points.',
      fields: [
        TemplateField(
          'title',
          'Welcome text',
          'Choose a topic and test yourself.',
        ),
      ],
      dataset: TemplateDataset(
        'Questions',
        {
          'topic': 'Topic',
          'question': 'Question',
          'a': 'Option A',
          'b': 'Option B',
          'c': 'Option C',
          'correct': 'Correct option (A, B or C)',
          'explanation': 'Answer explanation',
        },
        [
          {
            'topic': 'Everyday knowledge',
            'question': 'How many sides does a triangle have?',
            'a': 'Three',
            'b': 'Four',
            'c': 'Five',
            'correct': 'A',
            'explanation': 'A triangle has three sides.',
          },
          {
            'topic': 'Everyday knowledge',
            'question': 'Which direction is opposite to north?',
            'a': 'East',
            'b': 'South',
            'c': 'West',
            'correct': 'B',
            'explanation': 'North and south are opposite directions.',
          },
          {
            'topic': 'Everyday knowledge',
            'question': 'How many minutes are in an hour?',
            'a': '30',
            'b': '100',
            'c': '60',
            'correct': 'C',
            'explanation': 'One hour contains 60 minutes.',
          },
          {
            'topic': 'Science',
            'question': 'Which planet do we live on?',
            'a': 'Mars',
            'b': 'Earth',
            'c': 'Venus',
            'correct': 'B',
            'explanation': 'Earth is our home planet.',
          },
          {
            'topic': 'Science',
            'question':
                'At standard pressure, water freezes at which Celsius temperature?',
            'a': '0',
            'b': '50',
            'c': '100',
            'correct': 'A',
            'explanation':
                'Pure water freezes at 0 degrees Celsius at standard pressure.',
          },
          {
            'topic': 'Science',
            'question': 'Which organ pumps blood through the body?',
            'a': 'Lung',
            'b': 'Stomach',
            'c': 'Heart',
            'correct': 'C',
            'explanation':
                'The heart pumps blood through the circulatory system.',
          },
        ],
      ),
      build: buildQuiz,
    ),
    BotTemplate(
      id: 'crypto',
      name: 'Crypto prices',
      summary: 'Request current prices for five leading cryptocurrencies.',
      description:
          'Fetch the top five coins by market capitalization from CoinGecko only after /prices or Refresh. No API key or scheduled polling. Includes a shared cooldown and a friendly retry message for unavailable data or service failures. Keyless access has shared rate limits and is intended for testing and educational use.',
      fields: [
        TemplateField('currency', 'Quote currency (e.g. usd, eur)', 'usd'),
        TemplateField(
          'cooldown',
          'Minimum seconds between requests',
          '15',
          number: true,
        ),
      ],
      build: buildCrypto,
    ),
    BotTemplate(
      id: 'tasks',
      name: 'Personal task list',
      summary: 'Add, complete, reopen and delete tasks with pagination.',
      description:
          'Each person gets a private task list. Add a task with a message, browse five at a time, mark it done, reopen it or delete it.',
      fields: [TemplateField('title', 'List heading', 'Your tasks')],
      build: buildTasks,
    ),
    BotTemplate(
      id: 'library',
      name: 'Searchable library',
      summary: 'Browse categories, search content and save favorites.',
      description:
          'Publish articles, resources and file links. Each person can search titles and descriptions and keep a private favorites list. Sample links are placeholders to replace before use.',
      fields: [
        TemplateField(
          'title',
          'Welcome text',
          'Browse the library or search for a resource.',
        ),
      ],
      dataset: TemplateDataset(
        'Resources',
        {
          'category': 'Category',
          'title': 'Title',
          'description': 'Description or article text',
          'url': 'HTTP(S) link',
        },
        [
          {
            'category': 'Getting started',
            'title': 'Welcome guide',
            'description': 'Replace this sample with your own introduction.',
            'url': 'https://example.org/welcome',
          },
          {
            'category': 'Getting started',
            'title': 'Frequently asked questions',
            'description':
                'Answers to the questions your readers ask most often.',
            'url': 'https://example.org/faq',
          },
          {
            'category': 'Resources',
            'title': 'Reference notes',
            'description': 'A sample resource or downloadable file link.',
            'url': 'https://example.org/notes',
          },
        ],
      ),
      build: buildLibrary,
    ),
    BotTemplate(
      id: 'feedback',
      name: 'Feedback survey',
      summary: 'Ratings, written answers, review and an admin summary.',
      description:
          'A multi-step survey with Back and Cancel, a paginated review before submission, repeat-click protection and an admin report. Question kind is rating (1–5) or text.',
      fields: [
        TemplateField(
          'title',
          'Welcome text',
          'We would like to hear your feedback.',
        ),
      ],
      dataset: TemplateDataset(
        'Questions',
        {'prompt': 'Question', 'kind': 'Kind (rating or text)'},
        [
          {'prompt': 'How useful was your experience?', 'kind': 'rating'},
          {'prompt': 'What could we improve?', 'kind': 'text'},
          {'prompt': 'How likely are you to recommend it?', 'kind': 'rating'},
        ],
      ),
      requiresAdmin: true,
      build: buildFeedback,
    ),
    BotTemplate(
      id: 'requests',
      name: 'Requests and replies',
      summary: 'Submit a request, track its status and receive an admin reply.',
      description:
          'General-purpose requests for a community, team or service. Collect a subject and description, issue a tracking number, and let an admin reply, close or reopen the request.',
      fields: [
        TemplateField(
          'title',
          'Welcome text',
          'Send a request or check your previous requests.',
        ),
      ],
      requiresAdmin: true,
      build: buildRequests,
    ),
    BotTemplate(
      id: 'registration',
      name: 'Event registration',
      summary: 'Limited seats, registration and cancellation.',
      description:
          'Show upcoming events and available seats. People can register once or cancel. A single SQL write checks capacity, so competing requests cannot overbook an event. Admin counts: /registrations.',
      fields: [
        TemplateField(
          'title',
          'Welcome text',
          'Choose an event to see its details and available seats.',
        ),
      ],
      dataset: TemplateDataset(
        'Events',
        {
          'title': 'Event name',
          'details': 'Details, date and location',
          'capacity': 'Capacity',
        },
        [
          {
            'title': 'Community meetup',
            'details': 'Sample event — set your date, time and location.',
            'capacity': 20,
          },
          {
            'title': 'Introductory workshop',
            'details':
                'Sample workshop — replace these details before publishing.',
            'capacity': 12,
          },
        ],
      ),
      requiresAdmin: true,
      build: buildRegistration,
    ),
  ];

  static BotTemplateDraft create(
    BotTemplate template,
    Map<String, String> settings,
    List<Map<String, dynamic>> rows,
    String admin,
  ) {
    for (final field in template.fields) {
      final value = settings[field.key]?.trim() ?? '';
      if (value.isEmpty || value.length > 500) {
        throw BuilderFailure('Enter ${field.label} (up to 500 characters).');
      }
      if (value.contains('{{') || value.contains('}}')) {
        throw const BuilderFailure(
          'Template settings are literal text; add variable references in the action editor afterwards.',
        );
      }
    }
    if (template.requiresAdmin && !RegExp(r'^[1-9][0-9]*$').hasMatch(admin)) {
      throw const BuilderFailure('Enter the admin’s numeric Telegram ID.');
    }
    if (template.dataset != null) {
      if (rows.isEmpty || rows.length > 20) {
        throw const BuilderFailure('Use 1–20 sample rows.');
      }
      for (final row in rows) {
        for (final column in template.dataset!.columns.keys) {
          final value = row[column]?.toString().trim() ?? '';
          if (value.isEmpty || value.length > 800) {
            throw BuilderFailure(
              'Complete ${template.dataset!.columns[column]!} (up to 800 characters).',
            );
          }
          if ({'topic', 'category'}.contains(column) &&
              utf8.encode(value).length > 40) {
            throw const BuilderFailure(
              'Topic and category names can contain at most 40 UTF-8 bytes, leaving room for button callback data.',
            );
          }
          if (column == 'title' && value.length > 120) {
            throw const BuilderFailure(
              'Use at most 120 characters for a title.',
            );
          }
        }
      }
    }
    if (template.id == 'quiz' &&
        rows.any((r) => !{'A', 'B', 'C'}.contains(r['correct']))) {
      throw const BuilderFailure('Correct options must be A, B or C.');
    }
    if (template.id == 'feedback' &&
        rows.any((r) => !{'rating', 'text'}.contains(r['kind']))) {
      throw const BuilderFailure('Survey kinds must be rating or text.');
    }
    if (template.id == 'library' &&
        rows.any((r) {
          final uri = Uri.tryParse(r['url'].toString());
          return uri == null ||
              !{'http', 'https'}.contains(uri.scheme) ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty;
        })) {
      throw const BuilderFailure(
        'Each resource needs an HTTP(S) URL without credentials.',
      );
    }
    if (template.id == 'registration') {
      for (final row in rows) {
        final value = int.tryParse(row['capacity'].toString());
        if (value == null || value < 1 || value > 100000) {
          throw const BuilderFailure('Capacity must be between 1 and 100000.');
        }
        row['capacity'] = value;
      }
    }
    if (template.id == 'crypto') {
      if (!RegExp(r'^[a-z]{3,10}$').hasMatch(settings['currency'] ?? '')) {
        throw const BuilderFailure(
          'Enter a lowercase quote currency such as usd or eur.',
        );
      }
      final seconds = int.tryParse(settings['cooldown'] ?? '');
      if (seconds == null || seconds < 15 || seconds > 3600) {
        throw const BuilderFailure(
          'Use a cooldown between 15 and 3600 seconds.',
        );
      }
    }
    return template.build(settings, rows, admin);
  }
}

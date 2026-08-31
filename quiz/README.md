# Quiz bank — Improving Query Performance in MySQL 8

A 42-question bank covering every chapter, built the same way as the rest of
the course: **every factual answer is a measured fact from the live UrbanCart
database**, and every wrong option is a *real misconception* — something the
course explicitly caught engineers (or the optimizer) believing. Nothing here
is trivia; if a question exists, someone has shipped the wrong answer.

## How to use it

- **As a learner**: take each chapter's section right after finishing that
  chapter's labs — closed-book first, then verify. Many answers come with a
  `-- verify:` SQL block in [answers.md](answers.md); run it on your own
  container and watch the answer prove itself. That habit *is* the course.
- **As an instructor**: use the per-chapter sections as recap warm-ups before
  the next chapter's video, or assemble a final exam by sampling across the
  blueprint below. Distractor notes in answers.md tell you which misconception
  each wrong option represents — read them aloud when reviewing; they're the
  teaching moment.

Scoring guide: ≥80% per chapter → move on. Anything you missed, re-run the
matching lab exercise — the tag on each question points to it.

## Blueprint

| Section | Questions | Lessons covered | Emphasis |
|---|---|---|---|
| Chapter 0 | Q0.1–Q0.6 | 0.1, 0.4, 0.7 | execution order, join arithmetic, subquery scope, temp tables |
| Chapter 1 | Q1.1–Q1.8 | 1.1, 1.4, 1.8, 1.10 | lifecycle, EXPLAIN columns, honest measurement, finding targets |
| Chapter 2 | Q2.1–Q2.10 | 2.1, 2.4, 2.8 | index machinery, composite/covering, the five traps, statistics |
| Chapter 3 | Q3.1–Q3.10 | 3.1, 3.4, 3.8, 3.11 | shapes: filters, joins, grain, subquery forms |
| Chapter 4 | Q4.1–Q4.8 | 4.1, 4.4, 4.7, 4.14 | the loop, plan reading, pagination, discipline |

Question types: **[MC]** multiple choice · **[predict]** predict the number or
error, then run it · **[order]** put steps in order.

Files: [quiz.md](quiz.md) (questions only) · [answers.md](answers.md)
(key, explanations, misconception notes, verify SQL).

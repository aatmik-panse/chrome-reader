import {
  pgTable,
  uuid,
  text,
  timestamp,
  integer,
  real,
  jsonb,
  uniqueIndex,
  boolean,
  index,
} from "drizzle-orm/pg-core";

export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  googleId: text("google_id").notNull().unique(),
  email: text("email").notNull(),
  name: text("name").notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

export const readingPositions = pgTable(
  "reading_positions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    bookHash: text("book_hash").notNull(),
    bookTitle: text("book_title").notNull().default(""),
    chapterIndex: integer("chapter_index").notNull().default(0),
    scrollOffset: real("scroll_offset").notNull().default(0),
    percentage: real("percentage").notNull().default(0),
    updatedAt: timestamp("updated_at").defaultNow().notNull(),
  },
  (table) => [
    uniqueIndex("user_book_idx").on(table.userId, table.bookHash),
  ]
);

export const aiCache = pgTable("ai_cache", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  bookHash: text("book_hash").notNull(),
  requestType: text("request_type").notNull(),
  requestHash: text("request_hash").notNull(),
  response: jsonb("response").notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

export const highlights = pgTable(
  "highlights",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    clientId: text("client_id").notNull(),       // uuid from client (idempotency)
    bookHash: text("book_hash").notNull(),
    chapterIndex: integer("chapter_index").notNull(),
    startOffset: integer("start_offset").notNull(),
    length: integer("length").notNull(),
    contextBefore: text("context_before").notNull().default(""),
    contextAfter: text("context_after").notNull().default(""),
    text: text("text").notNull(),
    color: text("color").notNull(),
    note: text("note"),
    createdAt: timestamp("created_at").defaultNow().notNull(),
    updatedAt: timestamp("updated_at").defaultNow().notNull(),
    deletedAt: timestamp("deleted_at"),
  },
  (table) => [
    uniqueIndex("user_client_id_idx").on(table.userId, table.clientId),
  ]
);

export const vocabulary = pgTable(
  "vocabulary",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
    clientId: text("client_id").notNull(),
    word: text("word").notNull(),
    phonetic: text("phonetic"),
    audioUrl: text("audio_url"),
    definitions: jsonb("definitions").notNull(),
    contexts: jsonb("contexts").notNull(),
    stage: integer("stage").notNull().default(0),
    mastered: boolean("mastered").notNull().default(false),
    nextReviewAt: timestamp("next_review_at").notNull(),
    lastReviewAt: timestamp("last_review_at"),
    correctStreak: integer("correct_streak").notNull().default(0),
    createdAt: timestamp("created_at").defaultNow().notNull(),
    updatedAt: timestamp("updated_at").defaultNow().notNull(),
    deletedAt: timestamp("deleted_at"),
  },
  (t) => [
    uniqueIndex("vocab_user_client_id_idx").on(t.userId, t.clientId),
    index("vocab_user_word_idx").on(t.userId, t.word),
  ]
);

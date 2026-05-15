CREATE TABLE "vocabulary" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"client_id" text NOT NULL,
	"word" text NOT NULL,
	"phonetic" text,
	"audio_url" text,
	"definitions" jsonb NOT NULL,
	"contexts" jsonb NOT NULL,
	"stage" integer DEFAULT 0 NOT NULL,
	"mastered" boolean DEFAULT false NOT NULL,
	"next_review_at" timestamp NOT NULL,
	"last_review_at" timestamp,
	"correct_streak" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	"deleted_at" timestamp
);
--> statement-breakpoint
ALTER TABLE "vocabulary" ADD CONSTRAINT "vocabulary_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "vocab_user_client_id_idx" ON "vocabulary" USING btree ("user_id","client_id");--> statement-breakpoint
CREATE INDEX "vocab_user_word_idx" ON "vocabulary" USING btree ("user_id","word");
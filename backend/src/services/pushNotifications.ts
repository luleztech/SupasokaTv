import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { readFileSync } from 'node:fs';
import { env } from '../config/env';

type ServiceAccountLike = {
  project_id?: string;
  client_email?: string;
  private_key?: string;
};

function tryLoadServiceAccountFromJsonEnv(): ServiceAccountLike | null {
  const raw = env.fcmServiceAccountJson.trim();
  if (!raw) return null;
  try {
    return JSON.parse(raw) as ServiceAccountLike;
  } catch (_) {
    throw new Error('FCM_SERVICE_ACCOUNT_JSON is not valid JSON');
  }
}

function tryLoadServiceAccountFromFile(): ServiceAccountLike | null {
  const path = env.fcmServiceAccountPath.trim();
  if (!path) return null;
  try {
    const raw = readFileSync(path, 'utf-8');
    return JSON.parse(raw) as ServiceAccountLike;
  } catch (_) {
    throw new Error('Could not read/parse FCM_SERVICE_ACCOUNT_PATH json file');
  }
}

function ensureFirebaseApp(): void {
  if (getApps().length > 0) return;
  const fromJsonEnv = tryLoadServiceAccountFromJsonEnv();
  const fromFile = tryLoadServiceAccountFromFile();

  const projectId = (fromJsonEnv?.project_id ?? fromFile?.project_id ?? env.fcmProjectId).trim();
  const clientEmail = (fromJsonEnv?.client_email ?? fromFile?.client_email ?? env.fcmClientEmail).trim();
  const privateKey = (fromJsonEnv?.private_key ?? fromFile?.private_key ?? env.fcmPrivateKey).trim();
  if (!projectId || !clientEmail || !privateKey) {
    throw new Error(
      'FCM credentials missing. Use FCM_SERVICE_ACCOUNT_JSON, FCM_SERVICE_ACCOUNT_PATH, or (FCM_PROJECT_ID / FCM_CLIENT_EMAIL / FCM_PRIVATE_KEY).',
    );
  }
  initializeApp({
    credential: cert({
      projectId,
      clientEmail,
      privateKey,
    }),
  });
}

function topicForTarget(target: string): string {
  const t = target.trim().toLowerCase();
  if (t === 'premium') return 'premium_users';
  if (t === 'free') return 'free_users';
  return 'all_users';
}

export function checkPushConfiguration(): { ok: true } {
  ensureFirebaseApp();
  return { ok: true };
}

export async function sendPushToTopic(input: {
  title: string;
  body: string;
  target: string;
}): Promise<{ topic: string; messageId: string }> {
  ensureFirebaseApp();
  const title = input.title.trim();
  const body = input.body.trim();
  if (!title) throw new Error('title is required');
  const topic = topicForTarget(input.target);

  const messageId = await getMessaging().send({
    topic,
    notification: { title, body },
    data: {
      target: input.target.trim() || 'all',
      source: 'supaadmin',
    },
    android: {
      priority: 'high',
      notification: {
        // Must match viewer app Android channel id for heads-up / status-bar alerts.
        channelId: 'supasoka_high_importance',
        defaultSound: true,
      },
    },
  });
  return { topic, messageId };
}

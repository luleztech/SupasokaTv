import type { Pool } from 'pg';

/** Tanzania local calendar day for admin revenue reporting. */
const ADMIN_REVENUE_TZ = 'Africa/Dar_es_Salaam';

/** Successful payment = completed status with a positive amount. */
const SUCCESSFUL_PAYMENT_SQL = `status = 'COMPLETED' AND amount_tzs IS NOT NULL AND amount_tzs > 0`;

/** Best-effort completion instant: activation time, else last status update. */
const COMPLETED_AT_SQL = `COALESCE(to_timestamp(activated_at_ms / 1000.0), updated_at)`;

const COMPLETED_DAY_SQL = `DATE(timezone('${ADMIN_REVENUE_TZ}', ${COMPLETED_AT_SQL}))`;

export type PaymentHealthSummary = {
  total: number;
  pending: number;
  completed: number;
  failed: number;
  cancelled: number;
  expired: number;
  rejected: number;
  error: number;
  activated: number;
  totalCollectionsTzs: number;
  todayCollectionsTzs: number;
  todayCompleted: number;
};

export type PaymentHealthRecent = {
  orderId: string;
  publicId: string | null;
  planId: string | null;
  amountTzs: number;
  status: string;
  createdAt: string;
};

export type PaymentDailyRevenue = {
  day: string;
  count: number;
  totalTzs: number;
};

export async function fetchPaymentHealth(pool: Pool): Promise<{
  summary: PaymentHealthSummary;
  recent: PaymentHealthRecent[];
  dailyRevenue: PaymentDailyRevenue[];
  revenueTodayDay: string;
}> {
  const [statusRows, activated, totalCollections, todayRevenue, dailyRows, recent, todayDayRow] =
    await Promise.all([
    pool.query<{ status: string; count: string }>(
      `SELECT UPPER(COALESCE(status, 'PENDING')) AS status, COUNT(*)::text AS count
       FROM payment_intents
       GROUP BY UPPER(COALESCE(status, 'PENDING'))`,
    ),
    pool.query<{ count: string }>(
      `SELECT COUNT(*)::text AS count FROM payment_intents WHERE activated_at_ms IS NOT NULL`,
    ),
    pool.query<{ total_tzs: string }>(
      `SELECT COALESCE(SUM(amount_tzs), 0)::text AS total_tzs
       FROM payment_intents
       WHERE ${SUCCESSFUL_PAYMENT_SQL}`,
    ),
    pool.query<{ total_tzs: string; count: string }>(
      `SELECT COALESCE(SUM(amount_tzs), 0)::text AS total_tzs,
              COUNT(*)::text AS count
       FROM payment_intents
       WHERE ${SUCCESSFUL_PAYMENT_SQL}
         AND ${COMPLETED_DAY_SQL} = DATE(timezone('${ADMIN_REVENUE_TZ}', now()))`,
    ),
    pool.query<{ day: string; count: string; total_tzs: string }>(
      `SELECT ${COMPLETED_DAY_SQL}::text AS day,
              COUNT(*)::text AS count,
              COALESCE(SUM(amount_tzs), 0)::text AS total_tzs
       FROM payment_intents
       WHERE ${SUCCESSFUL_PAYMENT_SQL}
       GROUP BY 1
       ORDER BY 1 DESC
       LIMIT 14`,
    ),
    pool.query<{
      order_id: string;
      public_id: string | null;
      plan_id: string | null;
      amount_tzs: number | null;
      status: string;
      created_at: Date;
    }>(
      `SELECT order_id, public_id, plan_id, amount_tzs, status, created_at
       FROM payment_intents
       ORDER BY created_at DESC
       LIMIT 8`,
    ),
    pool.query<{ day: string }>(
      `SELECT DATE(timezone('${ADMIN_REVENUE_TZ}', now()))::text AS day`,
    ),
  ]);

  const summary: PaymentHealthSummary = {
    total: 0,
    pending: 0,
    completed: 0,
    failed: 0,
    cancelled: 0,
    expired: 0,
    rejected: 0,
    error: 0,
    activated: Number(activated.rows[0]?.count ?? '0') || 0,
    totalCollectionsTzs: Number(totalCollections.rows[0]?.total_tzs ?? '0') || 0,
    todayCollectionsTzs: Number(todayRevenue.rows[0]?.total_tzs ?? '0') || 0,
    todayCompleted: Number(todayRevenue.rows[0]?.count ?? '0') || 0,
  };

  for (const r of statusRows.rows) {
    const n = Number(r.count) || 0;
    summary.total += n;
    switch (r.status) {
      case 'COMPLETED':
        summary.completed += n;
        break;
      case 'FAILED':
        summary.failed += n;
        break;
      case 'CANCELLED':
        summary.cancelled += n;
        break;
      case 'EXPIRED':
        summary.expired += n;
        break;
      case 'REJECTED':
        summary.rejected += n;
        break;
      case 'ERROR':
        summary.error += n;
        break;
      default:
        summary.pending += n;
        break;
    }
  }

  return {
    summary,
    recent: recent.rows.map((r) => ({
      orderId: r.order_id,
      publicId: r.public_id,
      planId: r.plan_id,
      amountTzs: r.amount_tzs ?? 0,
      status: r.status,
      createdAt: r.created_at.toISOString(),
    })),
    dailyRevenue: dailyRows.rows.map((r) => ({
      day: r.day,
      count: Number(r.count) || 0,
      totalTzs: Number(r.total_tzs) || 0,
    })),
    revenueTodayDay: todayDayRow.rows[0]?.day ?? '',
  };
}

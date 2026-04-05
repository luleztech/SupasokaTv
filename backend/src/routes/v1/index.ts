import { Router } from 'express';
import { adminRouter } from './admin.routes';
import { authRouter } from './auth.routes';
import { healthRouter } from './health.routes';
import { publicRouter } from './public.routes';

export const v1Router = Router();

v1Router.use('/health', healthRouter);
v1Router.use('/public', publicRouter);
v1Router.use('/auth', authRouter);
v1Router.use('/admin', adminRouter);

// PM2 config for the Flavourly API only. Every command in the README names this app explicitly
// (`flavourly-api`), so the other apps already running under PM2 are never restarted or stopped.
//
// Vertical scaling: raise FLAVOURLY_INSTANCES (one worker per CPU core you can spare).
// Horizontal scaling: run the same folder + .env on more servers (shared MySQL + Redis) and list
// them in the Nginx upstream — see README "Scaling".
module.exports = {
  apps: [
    {
      name: 'flavourly-api',
      script: './src/pm2-entry.cjs',
      cwd: __dirname,
      exec_mode: 'cluster',
      instances: Number(process.env.FLAVOURLY_INSTANCES || 2),
      // Zero-downtime `pm2 reload flavourly-api`: a worker only gets traffic after it reports ready.
      wait_ready: true,
      listen_timeout: 20000,
      kill_timeout: 16000,
      max_memory_restart: '400M',
      node_args: '--max-old-space-size=384',
      exp_backoff_restart_delay: 200,
      env: { NODE_ENV: 'production' },
      out_file: './logs/out.log',
      error_file: './logs/error.log',
      merge_logs: true,
      time: true,
    },
  ],
};

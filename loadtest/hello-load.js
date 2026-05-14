// k6 load test against the hello-world service.
// Run with: k6 run loadtest/hello-load.js
//
// Override target URL: BASE_URL=https://hello.YOUR_NLB.sslip.io k6 run loadtest/hello-load.js
//
// Profile: ramp up to 50 VUs over 1m, hold 3m, ramp down 1m.
// Each VU is roughly 50 req/s, so peak ~2500 RPS. Tune lower if your nodes are small.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '1m', target: 10 },
    { duration: '2m', target: 50 },
    { duration: '2m', target: 100 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],         // <1% errors
    http_req_duration: ['p(95)<500'],       // 95th < 500ms
    errors: ['rate<0.01'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function () {
  const res = http.get(`${BASE_URL}/`);
  const ok = check(res, {
    'status is 200': (r) => r.status === 200,
  });
  errorRate.add(!ok);
  sleep(Math.random() * 0.5);
}

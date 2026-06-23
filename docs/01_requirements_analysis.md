# Requirements Analysis - Task Force 1 · CDO-05

<!-- Doc owner: <Nhóm CDO-05 leader>
     Status: Draft (W11 T2-T3) → Final (W11 T6 Pack #1) → Refined (W12 T4 Pack #2)
     Word target: 800-1500 từ -->

## 1. Đề tài context

<!-- Refer Nhóm AI's 01_requirements.md - restate ngắn gọn (1 paragraph).
     TF1 Triage Hub: CTO SaaS startup B2B, ~20k user, ~50 microservice.
     On-call team 8 engineer burnout, ~50+ alert/tuần, MTTR tăng.
     Build Triage Hub: alert → context gather → AI diagnose → Jira ticket → Slack notify.
     Human-in-the-loop, KHÔNG auto-remediation. -->

## 2. Infra non-functional requirements

| NFR | Target | Justification |
|---|---|---|
| Multi-tenant scale | ≥ 50 tenant | Production target |
| SLO p99 latency | < 1000ms | From AI API contract |
| Availability | ≥ 99.5% | Subscription SLA |
| Error rate | < 0.5% | Customer trust |
| Cost per tenant/month | $X | Budget allocation |
| Onboarding SLA | < 30 min | Sales requirement |
| Security baseline | IAM least-priv + audit 90d | Compliance |

## 3. Differentiation angle (KEY)

- **Angle chọn**: <serverless-first / K8s-heavy / managed-services / event-driven hybrid>
- **Why this angle**: <pick 1-2 axis: cost / reliability / ops / scalability - explain>
- **Trade-off chấp nhận**: <vd: cold start latency cho cost saving>
- **Locked T3 W11**: <date - show "fastest-commit wins" enforcement>

## 4. Comparison với nhóm cùng task force

<!-- TF1 có 2 CDO. So sánh angle với CDO còn lại trong TF1. -->

| Aspect | CDO-05 angle | Nhóm CDO khác |
|---|---|---|
| Compute pattern | <vd Lambda> | <vd EKS> |
| Storage | ... | ... |
| Cost profile | ... | ... |
| Ops complexity | ... | ... |
| Latency profile | ... | ... |
| **Win axis** | <...> | <...> |

## 5. Constraints

- **AWS only** (no multi-cloud)
- **Region**: <ap-southeast-1 default>
- **Budget**: $X / 2 tuần build
- **Code freeze**: T4 W12 18h

## 6. Open questions

- [ ] Q1: ... - *To resolve with Nhóm AI by T4 W11*

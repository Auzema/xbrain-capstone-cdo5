# Capstone Phase 2 — Task Force 1 · CDO-05

> **Đề tài**: Triage Hub — AIOps Incident Triage Automation
> **Client**: CTO SaaS startup B2B, ~20k user, ~50 microservice. On-call burnt out, MTTR tăng.
> **Team**: CDO-05 (Cloud/DevOps)
> **Task Force**: TF1
> **Timeline**: W11 (22/06–26/06) → W12 (29/06–03/07)

---

## Quick Links

| Document | Status | Pack |
|---|---|---|
| [Requirements Analysis](docs/01_requirements_analysis.md) | Draft | #1 |
| [Infra Design](docs/02_infra_design.md) | Draft | #1 |
| [Security Design](docs/03_security_design.md) | Draft | #1 |
| [Deployment Design](docs/04_deployment_design.md) | Draft | #1 |
| [Cost Analysis](docs/05_cost_analysis.md) | Skeleton | #1 → #2 |
| [Test & Eval Report](docs/07_test_eval_report.md) | — | #2 |
| [ADRs](docs/08_adrs.md) | Ongoing | #1 + #2 |

## Other Deliverables

| File | Due |
|---|---|
| [Standup Notes](standup-notes.md) | Daily 14h |
| [Curveball Responses](curveball-responses.md) | After each curveball |
| [Individual Pitches](individual-pitches.md) | W12 T4 |
| [Retrospective](retrospective.md) | W12 T4 |
| `SLIDES.pdf` | W12 T5 8h (code freeze) |
| `demo-video.mp4` | W12 T5 8h (code freeze) |

## Repo Structure

```
xbrain-captone-cdo5/
├── docs/
│   ├── 01_requirements_analysis.md
│   ├── 02_infra_design.md
│   ├── 03_security_design.md
│   ├── 04_deployment_design.md
│   ├── 05_cost_analysis.md
│   ├── 07_test_eval_report.md
│   ├── 08_adrs.md
│   └── assets/                    # diagrams, screenshots
├── infra/                         # Terraform / IaC
│   ├── modules/
│   │   ├── networking/
│   │   ├── compute/
│   │   ├── data/
│   │   ├── tenant-provision/
│   │   └── observability/
│   ├── environments/
│   │   ├── sandbox/
│   │   ├── staging/
│   │   └── prod/
│   └── README.md
├── manifests/                     # K8s / app configs (if applicable)
├── scripts/                       # Utility scripts
├── standup-notes.md
├── curveball-responses.md
├── individual-pitches.md
├── retrospective.md
└── README.md
```

## Checkpoint Checklist

### Progress #1 — EOD T4 W11 (light)
- [ ] `01_requirements_analysis.md` (draft)
- [ ] `02_infra_design.md` (draft + angle declared + multi-tenant approach)
- [ ] `08_adrs.md` (≥2 ADR cho key decisions)

### Evidence Pack #1 ⭐ — EOD T6 W11
- [ ] `01_requirements_analysis.md`
- [ ] `02_infra_design.md` (with multi-tenant approach)
- [ ] `03_security_design.md` (draft)
- [ ] `04_deployment_design.md` (draft)
- [ ] `05_cost_analysis.md` (skeleton)
- [ ] `08_adrs.md` (≥3 ADRs)
- [ ] Base infra (VPC + cluster + observability) chạy được

### Progress #2 — EOD T2 W12 (light)
- [ ] AI engine integration started
- [ ] Tenant onboarding flow draft

### Evidence Pack #2 ⭐ — EOD T4 W12 (code freeze 18h)
- [ ] All docs final
- [ ] `05_cost_analysis.md` **measured**
- [ ] `07_test_eval_report.md` **new** với chaos response evidence
- [ ] `08_adrs.md` final (≥5 ADRs)
- [ ] Platform infra deployed + integrated với AI engine
- [ ] git tag `final`

## References

- [Capstone Announcement](../xbrain-learners/capstone-phase2/W11_W12_capstone_announcement.md)
- [Evidence Pack Format](../xbrain-learners/capstone-phase2/reference/CAPSTONE_EVIDENCE_PACK_FORMAT.md)
- [TF1 Triage Hub Brief](../xbrain-learners/capstone-phase2/reference/TF1_TRIAGE_LEARNER.md)
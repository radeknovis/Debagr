# Sponsorship channels — ready-to-paste setup

Prepared 22 October 2026. **Selected channels: GitHub Sponsors + Ko-fi.**
Account activation is explicitly deferred at the owner's request. Keep these
drafts and disabled payment links ready; do not prompt for login, create
accounts, or configure payouts until activation is requested. Funding does not
block releasing the notarized app. No payment channel has been activated.
The GitHub API confirms that `radeknovis` has no Sponsors listing. The Sponsors
signup page is open but requires the owner's GitHub confirmation of access.
No Ko-fi account or handle has been verified.

## GitHub Sponsors

Open [Sponsors account setup](https://github.com/sponsors/accounts) as `radeknovis`.
After authentication, complete the application and use this copy:

**Short bio**

> I build developer tools that shorten the trip from code to a real device.

**Profile introduction**

> I’m Radek, the developer behind Debagr, a native macOS app that helps Claude
> Code, Codex, and terminal users install and launch signed apps through the Mac
> already paired with their iPhone—even across separate Wi-Fi networks.
>
> Sponsorship supports compatibility work, device testing, documentation, and
> signed releases. The preview currently manages one remote device, requires
> Wi-Fi and a private VPN, and has prior remote iPhone deployment evidence with
> Tailscale. iPad and other VPN providers still need full hardware acceptance.
> Cellular-only operation is unsupported.
>
> Support is optional. It funds ongoing work; it does not purchase a software
> license, priority support, or a guaranteed feature or delivery date. Thank you
> for helping make real-device development easier to verify and maintain.

**Draft monthly tiers**

| Tier | Amount | Description |
| --- | --- | --- |
| Supporter | $5/month | Help keep documentation, setup guides, and compatibility notes current. |
| Builder | $20/month | Help fund device testing and investigation of OS and Xcode changes. |
| Project sponsor | $100/month | Support sustained compatibility work and release maintenance. Optional public acknowledgment only with your consent. |

**Draft one-time tier**

> $25 — Help fund the next testing session. No recurring commitment or product entitlement.

**Welcome message**

> Thank you for supporting my work. Your sponsorship helps fund testing,
> compatibility fixes, and documentation. Preview requirements and known limits
> apply to everyone. Please never send pairing files, credentials, or unreviewed
> diagnostics in a public issue.

GitHub requires owner contact details, payout setup, tax information, 2FA, and
application approval. The owner must supply and submit those details. Eligibility
is based on open-source contributions; this Debagr repository is currently
private. Sponsorship setup does not authorize publishing its source or choosing
an open-source license. Published tier amounts cannot be edited in place; confirm
these draft amounts before publishing them.
[GitHub setup requirements](https://docs.github.com/en/sponsors/receiving-sponsorships-through-github-sponsors/setting-up-github-sponsors-for-your-personal-account).

## Ko-fi: one-time support

Use an existing verified creator page where possible. Otherwise the owner must
create an account, accept its terms, and connect PayPal or Stripe. Do not guess a
handle or publish someone else's page.
[Ko-fi getting started](https://help.ko-fi.com/hc/en-us/articles/360014098514-Getting-started-on-Ko-fi).

**Display name**: Radek · Debagr

**About**

> Help the next build travel further. I’m building Debagr, a native macOS tool
> for remote iPhone deployment through your paired Mac and a private VPN.
> One-time tips help fund compatibility work, hardware testing, documentation,
> and signed releases. This is optional support for ongoing development, not a
> software purchase or a promise of support or delivery dates.

**Suggested tip**: $5, with a custom amount allowed. Currency and payment-provider
settings must be confirmed by the owner. Review the provider's current fees and
information shown to supporters before activation.

**Thank-you message**

> Thanks for supporting Debagr. You’re helping fund device testing and the
> compatibility work behind each release. I appreciate it.

**Cover**: `cover.png` (1200 × 630). **Avatar**: `../AppIcon.png`.

## Activate the prepared integration

1. Verify the intended public payment page while logged out, including its
   account owner and available payment flow. Do not send a test payment unless
   the owner asks for one.
2. Copy `.github/FUNDING.yml.example` to `.github/FUNDING.yml`; enable only the
   verified channel fields. Never publish an unclaimed Ko-fi handle.
3. Set `DEBAGR_SPONSOR_URL` and/or `DEBAGR_KOFI_URL` in
   `Marketing/site/config.js` to the verified HTTPS URLs.
4. Update the site's channel status and preview it. The current page labels both
   channels as preparing and collects no payments.
5. Keep product checkout closed. Funding is independent of any future paid
   license, and no final commercial pricing has been announced.

No sponsor outreach has been sent. Public posting and repository visibility are
separate publication decisions; changing visibility exposes the entire history.

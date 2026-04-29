# Queue Management System

Queue and kiosk management platform for customer check-in, live queue handling, and staff operations.

## Tech stack

- React 18
- TypeScript
- Vite
- Tailwind CSS
- shadcn/ui
- Supabase (database, auth, edge functions)

## Prerequisites

- Node.js 20+
- npm 10+
- Supabase CLI (only needed for local DB/functions workflow)

## Local development

1. Clone the repository.
2. Install dependencies.
3. Start the dev server.

```sh
npm install
npm run dev
```

The app runs on port 8080 by default.

## Frontend environment variables

Create a local env file and set:

- VITE_SUPABASE_URL
- VITE_SUPABASE_PUBLISHABLE_KEY

## Available scripts

- npm run dev: Start local development server
- npm run build: Production build
- npm run build:dev: Development-mode build
- npm run preview: Preview built app
- npm run lint: Run ESLint
- npm run test: Run Vitest once
- npm run test:watch: Run Vitest in watch mode

## Dynamic billing integration

This project includes dynamic billing with:

- Editable plan prices from billing tables
- Paystack payment processing
- In-house commission tracking (gross_amount, commission_amount, net_amount)

Default plans:

- free (0 / forever, unlimited)
- starter (NGN 29,000 / month)
- professional (NGN 79,000 / month)
- enterprise (NGN 199,000 / month)

### Included billing flow

- Plan selection on company signup
- Unlimited free-plan onboarding without payment checkout
- Secure payment initialization through Supabase Edge Function
- Redirect to Paystack checkout
- Callback verification and payment status updates
- Super admin approval supports both paid and free requests
- Subscription creation on approval

### Admin login credentials

- Company admin username and password are the email/password entered during company signup.
- Super admin credentials are the email/password of the account that has the `super_admin` role in `public.user_roles`.

### Required Supabase secrets

Set these in your Supabase project:

```sh
supabase secrets set PAYSTACK_SECRET_KEY=sk_test_xxx
supabase secrets set PAYMENT_CALLBACK_URL=https://your-app-domain/payment/callback
```

Note: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are available automatically in Edge Functions.

### Deploy database and functions

```sh
supabase db push
supabase functions deploy payment-initialize
supabase functions deploy payment-verify
```

### Pricing and commission management

Update pricing without redeploying the frontend:

- Edit rows in public.billing_plans
- Edit rows in public.billing_plan_prices for each currency
- Set commission in public.platform_payment_settings (id = 1)

The Super Admin page can also manage plan prices directly, and signup reads updates live.

### Multi-currency support

- Signup and landing pricing support multiple currencies
- Selected checkout currency is stored in company_requests.selected_currency
- Payment initialization resolves amount using selected plan + currency

## Deployment

### Vercel

1. Import this repository in Vercel.
2. Configure frontend environment variables.
3. Deploy.

### Supabase

Ensure schema migrations and edge functions are deployed for payment and billing features.

## Printer bridge

The printer bridge service lives in printer-bridge/ and can be deployed separately where direct printer access is required.

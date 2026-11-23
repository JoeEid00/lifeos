import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/i18n.dart';
import '../../core/settings.dart';
import '../../data/repo.dart';
import '../../widgets/common.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _password.text;
    if (email.isEmpty || pass.length < 6) {
      setState(() => _error = context.t('Enter a valid email and a password of at least 6 characters'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final auth = ref.read(supabaseProvider).auth;
    try {
      if (_signUp) {
        final r = await auth.signUp(email: email, password: pass);
        if (r.session == null) {
          setState(() => _info = context.t('Check your email to confirm your account, then sign in.'));
        }
      } else {
        await auth.signInWithPassword(email: email, password: pass);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final settings = ref.watch(settingsProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: AppCard(
        padding: const EdgeInsets.all(28),
        child: AutofillGroup(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(context.t(_signUp ? 'Create your account' : 'Welcome back'), style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(context.t('Your goals, projects, habits and time — in one system.'),
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textDirection: TextDirection.ltr,
              decoration: deco(context, context.t('Email'), icon: Icons.alternate_email_rounded),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              textDirection: TextDirection.ltr,
              onSubmitted: (_) => _submit(),
              decoration: deco(context, context.t('Password'),
                  icon: Icons.lock_outline_rounded,
                  suffix: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            if (_info != null) ...[
              const SizedBox(height: 12),
              Text(_info!, style: TextStyle(color: cs.primary)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.t(_signUp ? 'Create account' : 'Sign in')),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {
                _signUp = !_signUp;
                _error = null;
                _info = null;
              }),
              child: Text(context.t(_signUp ? 'Already have an account? Sign in' : 'New here? Create an account')),
            ),
          ]),
        ),
      ),
    );

    final hero = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, const Color(0xFF7C3AED), const Color(0xFF0EA5E9)],
        ),
      ),
      padding: const EdgeInsets.all(48),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 56),
        const SizedBox(height: 24),
        Text('LifeOS', style: theme.textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text(context.t('Vision → Goals → Projects → Tasks → Planner → Review'),
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white.withValues(alpha: .9))),
        const SizedBox(height: 32),
        for (final f in ['Plan your week around what matters', 'Build habits with streaks and routines', 'Review progress with real data'])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(context.t(f), style: const TextStyle(color: Colors.white, fontSize: 15))),
            ]),
          ),
      ]),
    );

    final langToggle = TextButton.icon(
      onPressed: () => ref.read(settingsProvider.notifier).setLanguage(settings.languageCode == 'ar' ? 'en' : 'ar'),
      icon: const Icon(Icons.translate_rounded),
      label: Text(settings.languageCode == 'ar' ? 'English' : 'العربية'),
    );

    return Scaffold(
      body: SafeArea(
        child: wide
            ? Row(children: [
                Expanded(child: hero),
                Expanded(
                  child: Stack(children: [
                    Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: form)),
                    PositionedDirectional(top: 12, end: 12, child: langToggle),
                  ]),
                ),
              ])
            : Stack(children: [
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [cs.primary, const Color(0xFF8B5CF6)]),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.all_inclusive_rounded, color: Colors.white, size: 36),
                      ),
                      const SizedBox(height: 12),
                      Text('LifeOS', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 20),
                      form,
                    ]),
                  ),
                ),
                PositionedDirectional(top: 4, end: 4, child: langToggle),
              ]),
      ),
    );
  }
}

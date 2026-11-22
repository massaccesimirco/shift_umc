import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/access_failure.dart';
import '../../models/planning.dart';
import '../../providers/auth_providers.dart';
import 'login_screen.dart';
import 'duties_panel.dart';
import 'employees_panel.dart';
import 'weeks_panel.dart';
import 'password_dialog.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});
  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final id = ref.read(sessionUserProvider).asData?.value;
      if (id != null) ref.invalidate(currentProfileProvider(id));
    }
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(sessionUserProvider)
      .when(
        skipLoadingOnRefresh: false,
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (error, stack) => _AccountPage(
          message: accessErrorMessage(error),
          retry: () => ref.invalidate(sessionUserProvider),
        ),
        data: (id) {
          if (id == null) return const LoginScreen();
          return ref
              .watch(currentProfileProvider(id))
              .when(
                skipLoadingOnRefresh: false,
                loading: () => const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => _AccountPage(
                  message: accessErrorMessage(error),
                  retry: () => ref.invalidate(currentProfileProvider(id)),
                ),
                data: (profile) => _AccountPage(
                  profile: profile,
                  retry: () => ref.invalidate(currentProfileProvider(id)),
                ),
              );
        },
      );
}

// Mostro la prima schermata autenticata usando soltanto il profilo remoto.
class _AccountPage extends ConsumerStatefulWidget {
  const _AccountPage({this.profile, this.message, required this.retry});
  final UserProfile? profile;
  final String? message;
  final VoidCallback retry;
  @override
  ConsumerState<_AccountPage> createState() => _AccountPageState();
}

enum _AdminSection { duties, employees, weeks }

class _AccountPageState extends ConsumerState<_AccountPage> {
  _AdminSection? _section;
  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final message = widget.message;
    final retry = widget.retry;
    final managing = _section != null && profile?.role == UserRole.admin;
    final action = ref.watch(authActionProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          managing
              ? switch (_section!) {
                  _AdminSection.duties => 'Mansioni',
                  _AdminSection.employees => 'Dipendenti',
                  _AdminSection.weeks => 'Settimane',
                }
              : 'ShiftUMC',
        ),
        leading: managing
            ? IconButton(
                tooltip: 'Torna al profilo',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _section = null),
              )
            : null,
        actions: [
          TextButton.icon(
            onPressed: action.isLoading
                ? null
                : () => ref.read(authActionProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Esci'),
          ),
        ],
      ),
      body: SafeArea(
        child: managing
            ? switch (_section!) {
                _AdminSection.duties => DutiesPanel(userId: profile!.id),
                _AdminSection.employees => EmployeesPanel(userId: profile!.id),
                _AdminSection.weeks => WeeksPanel(userId: profile!.id),
              }
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (profile != null) ...[
                          Text(
                            'Benvenuto, ${profile.fullName}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          Chip(
                            label: Text(
                              profile.role == UserRole.admin
                                  ? 'Amministratore'
                                  : 'Dipendente',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(profile.email),
                          const SizedBox(height: 12),
                          const Text('Il tuo account è attivo.'),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: action.isLoading
                                ? null
                                : () async {
                                    final saved = await showDialog<bool>(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (_) =>
                                          PasswordDialog(userId: profile.id),
                                    );
                                    if (saved == true && context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Password aggiornata.'),
                                        ),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.password),
                            label: const Text('Cambia password'),
                          ),
                          if (profile.role == UserRole.admin) ...[
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: () => setState(
                                () => _section = _AdminSection.duties,
                              ),
                              icon: const Icon(Icons.work_outline),
                              label: const Text('Gestisci mansioni'),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () => setState(
                                () => _section = _AdminSection.employees,
                              ),
                              icon: const Icon(Icons.people_outline),
                              label: const Text('Gestisci dipendenti'),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () => setState(
                                () => _section = _AdminSection.weeks,
                              ),
                              icon: const Icon(Icons.calendar_month),
                              label: const Text('Gestisci settimane'),
                            ),
                          ],
                        ] else
                          Text(
                            message!,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        if (profile == null) ...[
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: action.isLoading
                                ? null
                                : () => ref
                                      .read(authActionProvider.notifier)
                                      .signOut(),
                            icon: const Icon(Icons.login),
                            label: const Text('Torna al login'),
                          ),
                        ],
                        const SizedBox(height: 24),
                        OutlinedButton(
                          onPressed: action.isLoading ? null : retry,
                          child: Text(
                            profile == null ? 'Riprova' : 'Aggiorna profilo',
                          ),
                        ),
                        if (action.hasError)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              accessErrorMessage(action.error!),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

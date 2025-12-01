import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Controllers
  final _emailOrUserCtrl = TextEditingController(); 
  final _fullNameCtrl = TextEditingController(); 
  final _usernameCtrl = TextEditingController();    
  final _emailCtrl = TextEditingController();       
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isLogin = true; 
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  
  // Checkbox Terms
  bool _agreeToTerms = false; 

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    final supabase = Supabase.instance.client;

    try {
      if (_isLogin) {
        // --- LOGIKA LOGIN ---
        String emailToLogin = _emailOrUserCtrl.text.trim();
        final password = _passCtrl.text;

        if (!emailToLogin.contains('@')) {
          final res = await supabase.from('profiles').select('email').eq('username', emailToLogin).maybeSingle(); 
          if (res == null) throw 'Username tidak ditemukan.';
          emailToLogin = res['email'];
        }

        await supabase.auth.signInWithPassword(email: emailToLogin, password: password);
      } else {
        // --- LOGIKA REGISTER ---
        final fullName = _fullNameCtrl.text.trim();
        final email = _emailCtrl.text.trim();
        final username = _usernameCtrl.text.trim();
        final password = _passCtrl.text;
        final confirm = _confirmPassCtrl.text;

        if (!_agreeToTerms) throw 'Anda harus menyetujui Syarat dan Ketentuan.';
        
        if (fullName.isEmpty) throw 'Nama Lengkap wajib diisi';
        if (fullName.contains(RegExp(r'[0-9]'))) throw 'Nama Lengkap tidak boleh mengandung angka.';

        if (username.isEmpty) throw 'Username wajib diisi';
        if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(username)) throw 'Username hanya boleh huruf, angka, titik, dan _';

        if (password != confirm) throw 'Password tidak sama!';
        if (password.length < 8) throw 'Password minimal 8 karakter';
        if (!password.contains(RegExp(r'[A-Z]'))) throw 'Password harus ada Huruf Besar (A-Z).';
        if (!password.contains(RegExp(r'[a-z]'))) throw 'Password harus ada Huruf Kecil (a-z).';
        if (!password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) throw 'Password harus ada Simbol.';

        // Proses Daftar
        await supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': fullName, 
            'username': username,  
          },
        );
        
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
             content: Text('Registrasi Berhasil! Silakan Login.'),
             backgroundColor: Colors.green,
           ));
           setState(() { 
             _isLogin = true; 
             _emailOrUserCtrl.text = username; 
             _passCtrl.clear();
             _agreeToTerms = false;
           });
           setState(() => _isLoading = false);
           return; 
        }
      }

      if (mounted && _isLogin) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
      }
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- POPUP LUPA PASSWORD ---
  Future<void> _showForgotPasswordDialog() async {
    final resetEmailCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Lupa Password"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Masukkan email untuk reset password."),
            const SizedBox(height: 16),
            TextField(controller: resetEmailCtrl, decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await Supabase.instance.client.auth.resetPasswordForEmail(resetEmailCtrl.text.trim());
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link reset dikirim!"), backgroundColor: Colors.green));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
              }
            },
            child: const Text("Kirim"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ambil warna tema
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isLogin ? 'Selamat Datang' : 'Buat Akun Baru',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: primaryColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _isLogin ? 'Masuk untuk jual beli barang' : 'Isi data diri Anda',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),

              // FORM LOGIN
              if (_isLogin) ...[
                TextField(
                  controller: _emailOrUserCtrl,
                  decoration: const InputDecoration(labelText: 'Email atau Username', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 16),
              ],

              // FORM REGISTER
              if (!_isLogin) ...[
                TextField(
                  controller: _fullNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nama Lengkap (Sesuai KTP)', prefixIcon: Icon(Icons.badge_outlined)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Alamat Email', prefixIcon: Icon(Icons.email_outlined)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameCtrl,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]'))],
                  decoration: const InputDecoration(labelText: 'Username (Unik)', prefixIcon: Icon(Icons.alternate_email)),
                ),
                const SizedBox(height: 16),
              ],

              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  helperText: !_isLogin ? 'Min 8 char, Huruf Besar, Kecil, & Simbol' : null,
                  helperMaxLines: 2,
                  suffixIcon: IconButton(icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscurePass = !_obscurePass)),
                ),
              ),

              if (!_isLogin) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPassCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Ulangi Password',
                    prefixIcon: const Icon(Icons.lock_reset),
                    suffixIcon: IconButton(icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: _agreeToTerms, 
                      activeColor: primaryColor,
                      onChanged: (val) => setState(() => _agreeToTerms = val ?? false)
                    ),
                    Expanded(child: Text("Saya setuju dengan Syarat & Ketentuan Layanan.", style: TextStyle(fontSize: 12, color: Colors.grey[700]))),
                  ],
                ),
              ],

              if (_isLogin) 
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _showForgotPasswordDialog, child: const Text("Lupa Password?"))),

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(_isLogin ? 'MASUK SEKARANG' : 'DAFTAR AKUN'),
              ),

              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_isLogin ? 'Belum punya akun?' : 'Sudah punya akun?'),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isLogin = !_isLogin;
                        _passCtrl.clear(); _confirmPassCtrl.clear(); _emailCtrl.clear(); 
                        _usernameCtrl.clear(); _fullNameCtrl.clear(); _agreeToTerms = false;
                      });
                    },
                    style: TextButton.styleFrom(foregroundColor: primaryColor),
                    child: Text(_isLogin ? 'Daftar disini' : 'Login disini', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
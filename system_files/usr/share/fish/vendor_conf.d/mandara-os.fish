# Rust in your home (see /etc/profile.d/mandara-rustup.sh).
set -gx RUSTUP_HOME $HOME/.rustup
set -gx CARGO_HOME $HOME/.cargo
if not test -e $RUSTUP_HOME; or not test -e $CARGO_HOME
    /usr/libexec/mandara-os/rustup-seed
end
fish_add_path --global --move $CARGO_HOME/bin

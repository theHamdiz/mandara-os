# Rust lives in your home: ~/.rustup and ~/.cargo, seeded from the image's
# stable toolchain the first time a shell starts.
export RUSTUP_HOME="$HOME/.rustup"
export CARGO_HOME="$HOME/.cargo"
if [ ! -e "$RUSTUP_HOME" ] || [ ! -e "$CARGO_HOME" ]; then
	/usr/libexec/mandara-os/rustup-seed
fi
case ":$PATH:" in
*":$CARGO_HOME/bin:"*) ;;
*) PATH="$CARGO_HOME/bin:$PATH" ;;
esac
export PATH

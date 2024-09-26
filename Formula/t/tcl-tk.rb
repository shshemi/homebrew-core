class TclTk < Formula
  desc "Tool Command Language"
  homepage "https://www.tcl-lang.org"
  url "https://downloads.sourceforge.net/project/tcl/Tcl/9.0.0/tcl9.0.0-src.tar.gz"
  mirror "https://fossies.org/linux/misc/tcl9.0.0-src.tar.gz"
  sha256 "3bfda6dbaee8e9b1eeacc1511b4e18a07a91dff82d9954cdb9c729d8bca4bbb7"
  license "TCL"

  livecheck do
    url :stable
    regex(%r{url=.*?/(?:tcl|tk).?v?(\d+(?:\.\d+)+)[._-]src\.t}i)
  end

  bottle do
    sha256 arm64_sequoia: "5c86b0e5af8d90d098b67726a67dcc2c6a526c8aac2cea25e8fce43e6f57839f"
    sha256 arm64_sonoma:  "2a456668a99adffe53485ceb07961201aac42e582434530ac9e32870a3ac3190"
    sha256 arm64_ventura: "c27c4de6f2e0059d9f8faa87d3f0dbffc5e86d93f4aa472fc2a032596f7e732e"
    sha256 sonoma:        "f72b0c08a6e75d91441f827dde205c772cf0777b9ed9be1a5217e662c40051d5"
    sha256 ventura:       "b7981ed65c43e615854eb40afda733fffa641d2f9d65d26f27cc6bfa90387de5"
    sha256 x86_64_linux:  "f3d4fa58e986a465068f64d36c0a98dd37c3ed74da79b796b9fc90b467ce5bce"
  end

  depends_on "openssl@3"

  uses_from_macos "zlib"

  on_linux do
    depends_on "freetype" => :build
    depends_on "pkg-config" => :build
    depends_on "libx11"
    depends_on "libxext"
  end

  conflicts_with "page", because: "both install `page` binaries"
  conflicts_with "the_platinum_searcher", because: "both install `pt` binaries"

  resource "critcl" do
    url "https://github.com/andreas-kupries/critcl/archive/refs/tags/3.3.1.tar.gz"
    sha256 "d970a06ae1cdee7854ca1bc571e8b5fe7189788dc5a806bce67e24bbadbe7ae2"
  end

  resource "tcllib" do
    url "https://downloads.sourceforge.net/project/tcllib/tcllib/2.0/tcllib-2.0.tar.xz"
    sha256 "642c2c679c9017ab6fded03324e4ce9b5f4292473b62520e82aacebb63c0ce20"
  end

  # There is no tcltls release compatible with TCL 9 so using latest HEAD
  # https://core.tcl-lang.org/tcltls/info/1505883e4a18b50e
  # Ref: https://sourceforge.net/p/tcl/mailman/tcl-core/thread/eab3a8bf-b846-45ef-a80c-6bc94d6dfe91@elmicron.de/
  resource "tcltls" do
    url "https://core.tcl-lang.org/tcltls/tarball/1505883e4a/tcltls-1505883e4a.tar.gz"
    sha256 "a57d7b6b3710e6966387f0b2269e6a014b7b8b2db736e44d982af5318adeefba"
  end

  resource "tk" do
    url "https://downloads.sourceforge.net/project/tcl/Tcl/9.0.0/tk9.0.0-src.tar.gz"
    mirror "https://fossies.org/linux/misc/tk9.0.0-src.tar.gz"
    sha256 "f166e3c20773c82243f753cef4b091d05267cb7f87da64be88cb2ca5a2ba027e"
  end

  # "https://downloads.sourceforge.net/project/incrtcl/%5Bincr%20Tcl_Tk%5D-4-source/itk%204.1.0/itk4.1.0.tar.gz"
  # would cause `bad URI(is not URI?)` error on 12/13 builds
  # Also need a newer release than available on SourceForce for TCL 9
  # so we use the GitHub mirror which is easier to access than Fossil
  resource "itk4" do
    url "https://github.com/tcltk/itk/archive/refs/tags/itk-4-2-3.tar.gz"
    sha256 "3eea66dfc57259d85ad741a01786b70ae4b3ae9774d27e24f7d0917c7451e94b"
  end

  def install
    odie "tk resource needs to be updated" if version != resource("tk").version

    args = %W[
      --prefix=#{prefix}
      --includedir=#{include}/tcl-tk
      --mandir=#{man}
      --disable-zipfs
      --enable-threads
      --enable-64bit
    ]

    ENV["TCL_PACKAGE_PATH"] = "#{HOMEBREW_PREFIX}/lib"
    cd "unix" do
      system "./configure", *args
      system "make"
      system "make", "install"
      system "make", "install-private-headers"
      bin.install_symlink "tclsh#{version.to_f}" => "tclsh"
    end

    # Let tk finds our new tclsh
    ENV.prepend_path "PATH", bin

    resource("tk").stage do
      cd "unix" do
        args << "--enable-aqua=yes" if OS.mac?
        system "./configure", *args, "--without-x", "--with-tcl=#{lib}"
        system "make"
        system "make", "install"
        system "make", "install-private-headers"
        bin.install_symlink "wish#{version.to_f}" => "wish"
      end
    end

    resource("critcl").stage do
      system bin/"tclsh", "build.tcl", "install"
    end

    resource("tcllib").stage do
      system "./configure", "--prefix=#{prefix}", "--mandir=#{man}"
      system "make", "install"
      system "make", "critcl"
      cp_r "modules/tcllibc", "#{lib}/"
      ln_s "#{lib}/tcllibc/macosx-x86_64-clang", "#{lib}/tcllibc/macosx-x86_64" if OS.mac?
    end

    resource("tcltls").stage do
      system "./configure", "--with-ssl=openssl",
                            "--with-openssl-dir=#{Formula["openssl@3"].opt_prefix}",
                            "--prefix=#{prefix}",
                            "--mandir=#{man}"
      system "make", "install"
    end

    resource("itk4").stage do
      itcl_dir = lib.glob("itcl*").last
      # Workaround to build non-release tarball by using TEA files from itcl
      odie "Update `itk4` build step!" if Pathname("tclconfig").exist?
      Pathname.pwd.install_symlink buildpath/"pkgs/#{itcl_dir.basename}/tclconfig"

      args = %W[
        --prefix=#{prefix}
        --exec-prefix=#{prefix}
        --with-tcl=#{lib}
        --with-tclinclude=#{include}/tcl-tk
        --with-tk=#{lib}
        --with-tkinclude=#{include}/tcl-tk
        --with-itcl=#{itcl_dir}
      ]
      system "./configure", *args
      system "make"
      system "make", "install"
    end

    # Rename all section 3 man pages in the Debian/Ubuntu style, to avoid conflicts
    man3.glob("*.3") { |file| file.rename("#{file}tcl") }

    # Use the sqlite-analyzer formula instead
    # https://github.com/Homebrew/homebrew-core/pull/82698
    rm bin/"sqlite3_analyzer"
  end

  def caveats
    <<~EOS
      The sqlite3_analyzer binary is in the `sqlite-analyzer` formula.
    EOS
  end

  test do
    assert_match "#{HOMEBREW_PREFIX}/lib", pipe_output("#{bin}/tclsh", "puts $auto_path\n")
    assert_equal "honk", pipe_output("#{bin}/tclsh", "puts honk\n").chomp

    # Fails with: no display name and no $DISPLAY environment variable
    return if OS.linux? && ENV["HOMEBREW_GITHUB_ACTIONS"]

    test_itk = <<~EOS
      # Check that Itcl and Itk load, and that we can define, instantiate,
      # and query the properties of a widget.


      # If anything errors, just exit
      catch {
          package require Itcl
          package require Itk

          # Define class
          itcl::class TestClass {
              inherit itk::Toplevel
              constructor {args} {
                  itk_component add bye {
                      button $itk_interior.bye -text "Bye"
                  }
                  eval itk_initialize $args
              }
          }

          # Create an instance
          set testobj [TestClass .#auto]

          # Check the widget has a bye component with text property "Bye"
          if {[[$testobj component bye] cget -text]=="Bye"} {
              puts "OK"
          }
      }
      exit
    EOS
    assert_equal "OK\n", pipe_output("#{bin}/wish", test_itk), "Itk test failed"
  end
end

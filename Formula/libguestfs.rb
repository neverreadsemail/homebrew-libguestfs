require "digest"
require "options"

class OsxfuseRequirement < Requirement
  fatal true

  satisfy(build_env: false) { self.class.binary_osxfuse_installed? }

  def self.binary_osxfuse_installed?
    File.exist?("/usr/local/include/fuse/fuse.h") &&
      !File.symlink?("/usr/local/include/fuse")
  end

  env do
    unless HOMEBREW_PREFIX.to_s == "/usr/local"
      ENV.append_path "HOMEBREW_LIBRARY_PATHS", "/usr/local/lib"
      ENV.append_path "HOMEBREW_INCLUDE_PATHS", "/usr/local/include/fuse"
    end
  end

  def message
    "macFUSE is required to build libguestfs. Please run `brew install --cask macfuse` first."
  end
end

class Libguestfs < Formula
  desc "Tools for accessing and modifying virtual machine disk images"
  homepage "https://libguestfs.org/"
  # 1.48.4 is the latest stable release, but there have been lots of macOS
  # related patches since then. build from development until I find the minimum
  # set of required patches.
  # url "https://libguestfs.org/download/1.48-stable/libguestfs-1.48.4.tar.gz"
  # sha256 "9dc22b6c5a45f19c2cba911a37b3a8d86f62744521b10eb53c3d3907e5080312"
  url "https://libguestfs.org/download/1.49-development/libguestfs-1.49.5.tar.gz"
  sha256 "7923af8a5e2aa44268a5fed3cfb0634884e6562c88f46af65f066ce6a74547c4"
  head "https://github.com/libguestfs/libguestfs.git"

  depends_on "autoconf" => :build
  depends_on "automake" => :build
  depends_on "bison" => :build # macOS bison is one minor revision too old
  depends_on "gnu-sed" => :build # some of the makefiles expect gnu sed functionality
  depends_on "libtool" => :build
  depends_on "ocaml" => :build
  depends_on "ocaml-findlib" => :build
  depends_on "pkg-config" => :build
  depends_on "augeas"
  depends_on "cdrtools"
  depends_on "coreutils"
  depends_on "cpio"
  depends_on "flex"
  depends_on "glib"
  depends_on "gperf"
  depends_on "hivex"
  depends_on "jansson"
  depends_on "libmagic"
  depends_on "libvirt"
  depends_on "pcre"
  depends_on "qemu"
  depends_on "readline"
  depends_on "xz"

  uses_from_macos "libxml2"
  uses_from_macos "ncurses"

  on_macos do
    depends_on OsxfuseRequirement => :build
  end

  # the linux support is a bit of a guess, since homebrew doesn't currently build bottles for libvirt
  # that means brew test-bot's --build-bottle will fail under ubuntu-latest runners
  on_linux do
    depends_on "libcap"
    depends_on "libfuse"
  end

  # Since we can't build an appliance, the recommended way is to download a fixed one.
  resource "fixed_appliance" do
    url "file:///tmp/appliance-1.44.0.tar.xz"
    sha256 "622b222c18882455e55745531b1d06e4663b25558e5f1123a375ab6da346042c"
  end

  # stable do
  #   patch do
  #     url "https://github.com/libguestfs/libguestfs/commit/6c0e5d7f8f2a8eaddadbc34c08f8a1ed095626b0.diff"
  #     sha256 "e1d692c864646db3f0bc516f2bf595d878ee83ec4cf71d18c898e192fec32f04"
  #   end
  #   patch do
  #     url "https://github.com/libguestfs/libguestfs/commit/ef947a9d3ba8e2c55a05a25e8b8e55d1f3094f72.diff"
  #     sha256 "14cae217576bc2fb399cfafb11cf8c545998a29dfe913dcde1cb5affd0e1bd10"
  #   end
  #   patch do
  #     url "https://github.com/libguestfs/libguestfs/commit/8d5063774111800b907742cdab19a4fde530b325.diff"
  #     sha256 "7dc6bc945261ab7179f1f266319c9a5ebec46ce4a9879bce3513bc1da5066380"
  #   end
  # end
  patch :DATA

  def install
    ENV["FUSE_CFLAGS"] = "-D_FILE_OFFSET_BITS=64 -D_DARWIN_USE_64_BIT_INODE -I/usr/local/include/fuse"
    ENV["FUSE_LIBS"] = "-lfuse -pthread -liconv"
    ENV["LC_ALL"] = "C"
    %w[
      ncurses
      augeas
      jansson
      hivex
    ].each do |ext|
      ENV.prepend_path "PKG_CONFIG_PATH", Formula[ext].opt_lib/"pkgconfig"
    end

    args = [
      "--disable-dependency-tracking",
      "--disable-silent-rules",
      "--prefix=#{prefix}",
      "--with-distro=DARWIN",
      "--disable-probes",
      "--disable-appliance",
      "--disable-daemon",
      "--disable-ocaml",
      "--disable-lua",
      "--disable-haskell",
      "--disable-erlang",
      "--disable-gobject",
      "--disable-golang",
      "--disable-ruby",
      "--disable-golang",
      "--disable-php",
      "--disable-perl",
      "--disable-python",
    ]

    ENV["HAVE_RPM_FALSE"] = "#"
    ENV["HAVE_DPKG_FALSE"] = "#"
    ENV["HAVE_PACMAN_FALSE"] = "#"

    if Options.create(@flags).include?("git")
      system "git", "submodule", "update", "--init"
    end
    system "autoreconf", "-i"

    system "./configure", *args

    ENV.deparallelize { system "make" }

    libguestfs_path = "#{prefix}/var/libguestfs-appliance"
    mkdir_p libguestfs_path
    resource("fixed_appliance").stage(libguestfs_path)
    system "make", "INSTALLDIRS=vendor", "DESTDIR=#{buildpath}", "install"

    bin.install Dir["#{buildpath}/#{prefix}/bin/*"]
    include.install "#{buildpath}/#{prefix}/include/guestfs.h"
    lib.install Dir["#{buildpath}/#{prefix}/lib/*"]
    man1.install Dir["#{buildpath}/#{prefix}/share/man/man1/*"]
    man3.install Dir["#{buildpath}/#{prefix}/share/man/man3/*"]
    man5.install Dir["#{buildpath}/#{prefix}/share/man/man5/*"]

  end

  def caveats
    <<~EOS
      A fixed appliance is required for libguestfs to work on Mac OS X.
      This formula downloads the appliance and places it in:
      #{prefix}/var/libguestfs-appliance

      To use the appliance, add the following to your shell configuration:
      export LIBGUESTFS_PATH=#{prefix}/var/libguestfs-appliance
      and use libguestfs binaries in the normal way.

      For compilers to find libguestfs you may need to set:
        export LDFLAGS="-L#{prefix}/lib"
        export CPPFLAGS="-I#{prefix}/include"

      For pkg-config to find libguestfs you may need to set:
        export PKG_CONFIG_PATH="#{prefix}/lib/pkgconfig"

    EOS
  end

  test do
    ENV["LIBGUESTFS_PATH"] = "#{prefix}/var/libguestfs-appliance"
    system "make", "-j1", "quickcheck"
  end
end
__END__
diff --git a/lib/Makefile.am b/lib/Makefile.am
index 212bcb94a..84aa4297b 100644
--- a/lib/Makefile.am
+++ b/lib/Makefile.am
@@ -178,10 +178,11 @@ libvirt_is_version_SOURCES = libvirt-is-version.c
 
 libvirt_is_version_LDADD = \
 	$(LIBVIRT_LIBS) \
-	$(LTLIBINTL)
+	$(LTLIBINTL) \
+	../gnulib/lib/libgnu.la
 
 libvirt_is_version_CPPFLAGS = \
-	-DLOCALEBASEDIR=\""$(datadir)/locale"\"
+	-DLOCALEBASEDIR=\""$(datadir)/locale"\" -I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib
 
 libvirt_is_version_CFLAGS = \
 	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
diff --git a/lib/handle.c b/lib/handle.c
index 290652d8c..d405768d7 100644
--- a/lib/handle.c
+++ b/lib/handle.c
@@ -22,6 +22,7 @@
  */
 
 #include <config.h>
+#include <errno.h>
 
 #include <stdio.h>
 #include <stdlib.h>

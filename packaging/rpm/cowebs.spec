Name:           cowebs
Version:        @VERSION@
Release:        @RELEASE@%{?dist}
Summary:        COWebs cross-platform developer workstation controller
License:        MIT
BuildArch:      @RPM_ARCH@

%description
Deterministic profile planning, least-privilege installation, diagnostics,
journaling, and resumable setup for the COWebs dev-setup product.

%install
install -D -m 0755 %{_sourcedir}/cowebs %{buildroot}%{_bindir}/cowebs
install -D -m 0644 %{_sourcedir}/package-catalog.v3.json %{buildroot}%{_datadir}/cowebs/catalog/package-catalog.v3.json
install -D -m 0644 %{_sourcedir}/profile-catalog.v3.json %{buildroot}%{_datadir}/cowebs/catalog/profile-catalog.v3.json

%files
%{_bindir}/cowebs
%{_datadir}/cowebs/catalog/package-catalog.v3.json
%{_datadir}/cowebs/catalog/profile-catalog.v3.json

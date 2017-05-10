package LogPeriodic::BuildLib;

use strict;

use File::Temp;
use Cwd;

require Exporter;
use base 'Exporter';
our @EXPORT = qw(sys);



sub fpm {
    my $args = shift;

    my $cwd = cwd();

    $args->{url} //= 'https://logperiodic.com';
    $args->{license} //= 'GPL version 3';
    $args->{maintainer} //= 'Log Periodic <support@logperiodic.com>';


    die "need to install fpm ( https://github.com/jordansissel/fpm )"
        if !`which fpm`;

    my $tmp = File::Temp::tempdir(CLEANUP => 1);

    sys("mkdir -p dist");

    foreach my $type (@{ $args->{types} }) {
        foreach my $src (keys %{ $args->{files} }) {
            my $dest = "$tmp/$args->{files}->{$src}";

            my $dest_path = $dest;
            $dest_path =~ s{[^/]+\z}{};

            sys("mkdir -p $dest_path") if !-d $dest_path;
            sys("cp $src $dest");
        }

        foreach my $src (keys %{ $args->{dirs} }) {
            my $dest = "$tmp/$args->{dirs}->{$src}";

            sys("mkdir -p $dest");
            sys("cp -r $src/* $dest");
        }


        my $changelog = '';

        if (exists $args->{changelog}) {
            my $changelog_path = "$cwd/$args->{changelog}";

            if ($type eq 'deb') {
                $changelog = qq{ --deb-changelog "$changelog_path" };
            } elsif ($type eq 'rpm') {
                ## FIXME: fpm breaks?
                #$changelog = qq{ --rpm-changelog "$changelog_path" };
            } else {
                die "unknown type: $type";
            }
        }


        my $config_files = '';

        foreach my $config_file (@{ $args->{config_files} }) {
            $config_files .= "--config-files '$config_file' ";
        }


        my $deps_list;

        if ($type eq 'deb') {
            $deps_list = $args->{deps_deb} || $args->{deps};
        } elsif ($type eq 'rpm') {
            $deps_list = $args->{deps_rpm};
        }

        my $deps = '';

        foreach my $dep (@$deps_list) {
            $deps .= "-d '$dep' ";
        }


        my $postinst = '';

        if (exists $args->{postinst}) {
            $postinst = qq{ --after-install "$cwd/$args->{postinst}" };
        }


        my $cmd = qq{
            cd dist ; fpm
              -n "$args->{name}"
              -s dir -t $type
              -v $args->{version}

              --url "$args->{url}"
              --description "$args->{description}"
              --license "$args->{license}"
              --maintainer "$args->{maintainer}"
              --vendor ''

              $deps
              $changelog
              $postinst
              $config_files

              -f -C $tmp .
        };

        $cmd =~ s/\s+/ /g;
        $cmd =~ s/^\s*//;

        sys($cmd);
    }
}


sub sys {
    my $cmd = shift;
    print "$cmd\n";
    system($cmd) && die;
}



my $version_cache;

sub get_version {
    my $dist = shift;

    return $version_cache->{$dist} if defined $version_cache->{$dist};

    $version_cache->{$dist} = `git describe --tags --match '$dist-*'`;
    chomp $version_cache->{$dist};

    $version_cache->{$dist} =~ s/^$dist-//;

    ## Add a "0" to fix issue where dpkg dies if a version component doesn't contain any base-10 digits
    ## (which happens if the first 7 hex digits in a hash are all [a-f])
    $version_cache->{$dist} =~ s/-g([0-9a-f]+)$/-0g$1/;

    die "couldn't find version for $dist" if !$version_cache->{$dist};

    return $version_cache->{$dist};
}




sub upload {
    my $dir = "$ENV{HOME}/logp-internal";

    die "unable to find ~/logp-internal files. run 's3fs logp-internal /home/doug/logp-internal/'"
        if !-f "$dir/s3fs-mounted";

    sys(qq{ cp -n dist/*.deb $dir/amd64/ });
    sys(qq{cd $dir/amd64 ; dpkg-scanpackages amd64/ > amd64/Packages});
    sys(qq{cd $dir/amd64 ; apt-ftparchive release amd64/ > amd64/Release});
    sys(qq{gpg -a -b -u 'Log Periodic Ltd.' < $dir/amd64/Release > $dir/amd64/Release.gpg});
}




1;

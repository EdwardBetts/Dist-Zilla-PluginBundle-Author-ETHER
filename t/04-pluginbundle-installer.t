use strict;
use warnings;

use Test::More 0.96;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::Deep '!none';
use Test::DZil;
use Test::Fatal;
use Path::Tiny 0.062;
use Module::Runtime 'require_module';
use List::Util 1.33 'none';

use Test::Needs qw(
    Dist::Zilla::Plugin::ModuleBuildTiny
);

use Test::File::ShareDir -share => { -dist => { 'Dist-Zilla-PluginBundle-Author-ETHER' => 'share' } };

use lib 't/lib';
use Helper;
use NoNetworkHits;
use NoPrereqChecks;

subtest 'installer = MakeMaker' => sub {
    my $tzil = Builder->from_config(
        { dist_root => 'does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    'GatherDir',
                    [ '@Author::ETHER' => {
                        '-remove' => \@REMOVED_PLUGINS,
                        server => 'none',
                        installer => 'MakeMaker',
                        'RewriteVersion::Transitional.skip_version_provider' => 1,
                      },
                    ],
                ),
                path(qw(source lib MyDist.pm)) => "package MyDist;\n\n1",
                path(qw(source Changes)) => '',
            },
        },
    );

    assert_no_git($tzil);

    $tzil->chrome->logger->set_debug(1);
    is(
        exception { $tzil->build },
        undef,
        'build proceeds normally',
    );

    # check that everything we loaded is properly declared as prereqs
    all_plugins_in_prereqs($tzil,
        exempt => [ 'Dist::Zilla::Plugin::GatherDir' ],     # used by us here
        additional => [ 'Dist::Zilla::Plugin::MakeMaker' ], # via installer option
    );

    cmp_deeply(
        [ $tzil->plugin_named('@Author::ETHER/MakeMaker') ],
        [ methods(default_jobs => 9) ],
        'installer configuration settings are properly added to the payload',
    );

    my $build_dir = path($tzil->tempdir)->child('build');
    my @found_files;
    $build_dir->visit(
        sub { push @found_files, $_->relative($build_dir)->stringify if -f },
        { recurse => 1 },
    );

    cmp_deeply(
        \@found_files,
        all(
            superbagof('Makefile.PL'),
            code(sub { none { $_ eq 'Build.PL' } @{$_[0]} }),
        ),
        'Makefile.PL (and no other build file) was generated by the pluginbundle',
    );

    my $prereq_reporter = path($build_dir)->child('t', '00-report-prereqs.t')->slurp_utf8;
    unlike(
        $prereq_reporter,
        qr/^use Module::Metadata;$/m,
        'Module::Metadata is not used as the version extractor for [Test::ReportPrereqs]',
    );
    like(
        $prereq_reporter,
        qr/^use ExtUtils::MakeMaker;$/m,
        'EUMM is used as the version extractor for [Test::ReportPrereqs]',
    );

    diag 'got log messages: ', explain $tzil->log_messages
        if not Test::Builder->new->is_passing;
};

subtest 'installer = MakeMaker, ModuleBuildTiny' => sub {
    SKIP: {
    # MBT is already a prereq of things in our runtime recommends list
    skip('[ModuleBuildTiny] not installed', 9)
        if not eval { require_module 'Dist::Zilla::Plugin::ModuleBuildTiny'; 1 };

    my $tzil = Builder->from_config(
        { dist_root => 'does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    'GatherDir',
                    [ '@Author::ETHER' => {
                        '-remove' => \@REMOVED_PLUGINS,
                        server => 'none',
                        installer => [ qw(MakeMaker ModuleBuildTiny) ],
                        'RewriteVersion::Transitional.skip_version_provider' => 1,
                        'Test::MinimumVersion.max_target_perl' => '5.008',
                      },
                    ],
                ),
                path(qw(source lib MyModule.pm)) => "package MyModule;\n\n1",
                path(qw(source Changes)) => '',
            },
        },
    );

    assert_no_git($tzil);

    $tzil->chrome->logger->set_debug(1);
    is(
        exception { $tzil->build },
        undef,
        'build proceeds normally',
    );

    # check that everything we loaded is properly declared as prereqs
    all_plugins_in_prereqs($tzil,
        exempt => [ 'Dist::Zilla::Plugin::GatherDir' ],     # used by us here
        additional => [
            'Dist::Zilla::Plugin::MakeMaker',       # via installer option
            'Dist::Zilla::Plugin::ModuleBuildTiny', # ""
        ],
    );

    is($tzil->distmeta->{x_static_install}, 1, 'build is marked as eligible for static install');

    cmp_deeply(
        $tzil->distmeta->{prereqs}{develop}{requires},
        superhashof({
            'Dist::Zilla::Plugin::ModuleBuildTiny' => '0.012',
        }),
        'installer prereq version is added',
    ) or diag 'got dist metadata: ', explain $tzil->distmeta;

    cmp_deeply(
        [
            $tzil->plugin_named('@Author::ETHER/MakeMaker'),
            $tzil->plugin_named('@Author::ETHER/ModuleBuildTiny'),
        ],
        [
            methods(default_jobs => 9),
            methods(default_jobs => 9),
        ],
        'installer configuration settings are properly added to the payload',
    );

    my $build_dir = path($tzil->tempdir)->child('build');
    my @found_files;
    $build_dir->visit(
        sub { push @found_files, $_->relative($build_dir)->stringify if -f },
        { recurse => 1 },
    );

    cmp_deeply(
        \@found_files,
        superbagof(qw(
            Makefile.PL
            Build.PL
        )),
        'both Makefile.PL and Build.PL were generated by the pluginbundle',
    );

    my $prereq_reporter = path($build_dir)->child('t', '00-report-prereqs.t')->slurp_utf8;
    like(
        $prereq_reporter,
        qr/^use Module::Metadata;$/m,
        'Module::Metadata is used as the version extractor for [Test::ReportPrereqs]',
    );
    unlike(
        $prereq_reporter,
        qr/^use ExtUtils::MakeMaker;$/m,
        'EUMM is not used as the version extractor for [Test::ReportPrereqs]',
    );

    diag 'got log messages: ', explain $tzil->log_messages
        if not Test::Builder->new->is_passing;
} };

subtest 'installer = none' => sub {
    my $tzil = Builder->from_config(
        { dist_root => 'does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    'GatherDir',
                    [ '@Author::ETHER' => {
                        '-remove' => [ @REMOVED_PLUGINS, 'InstallGuide' ],
                        server => 'none',
                        installer => 'none',
                        'RewriteVersion::Transitional.skip_version_provider' => 1,
                      },
                    ],
                ),
                path(qw(source lib MyDist.pm)) => "package MyDist;\n\n1",
                path(qw(source Changes)) => '',
            },
        },
    );

    assert_no_git($tzil);

    $tzil->chrome->logger->set_debug(1);
    is(
        exception { $tzil->build },
        undef,
        'build proceeds normally',
    );

    is(@{ $tzil->plugins_with('-InstallerTool') }, 0, 'no installers configured');

    my $build_dir = path($tzil->tempdir)->child('build');
    my $prereq_reporter = path($build_dir)->child('t', '00-report-prereqs.t')->slurp_utf8;
    unlike(
        $prereq_reporter,
        qr/^use Module::Metadata;$/m,
        'Module::Metadata is not used as the version extractor for [Test::ReportPrereqs]',
    );
    like(
        $prereq_reporter,
        qr/^use ExtUtils::MakeMaker;$/m,
        'EUMM is used as the version extractor for [Test::ReportPrereqs]',
    );

    diag 'got log messages: ', explain $tzil->log_messages
        if not Test::Builder->new->is_passing;
};

subtest 'installer = ModuleBuildTiny, StaticInstall.mode = off' => sub {
    SKIP: {
    # MBT is already a prereq of things in our runtime recommends list
    skip('[ModuleBuildTiny] not installed', 8)
        if not eval { require_module 'Dist::Zilla::Plugin::ModuleBuildTiny'; 1 };

    my $tzil = Builder->from_config(
        { dist_root => 'does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    'GatherDir',
                    [ '@Author::ETHER' => {
                        '-remove' => \@REMOVED_PLUGINS,
                        server => 'none',
                        installer => [ 'ModuleBuildTiny' ],
                        'RewriteVersion::Transitional.skip_version_provider' => 1,
                        'Test::MinimumVersion.max_target_perl' => '5.008',
                        'StaticInstall.mode' => 'off',
                      },
                    ],
                ),
                path(qw(source lib MyModule.pm)) => "package MyModule;\n\n1",
                path(qw(source Changes)) => '',
            },
        },
    );

    assert_no_git($tzil);

    $tzil->chrome->logger->set_debug(1);
    is(
        exception { $tzil->build },
        undef,
        'build proceeds normally',
    );

    # check that everything we loaded is properly declared as prereqs
    all_plugins_in_prereqs($tzil,
        exempt => [ 'Dist::Zilla::Plugin::GatherDir' ],     # used by us here
        additional => [
            'Dist::Zilla::Plugin::ModuleBuildTiny', # ""
        ],
    );

    is($tzil->distmeta->{x_static_install}, 0, 'build is marked as not eligible for static install (by explicit request)');

    cmp_deeply(
        $tzil->distmeta->{prereqs}{develop}{requires},
        superhashof({
            'Dist::Zilla::Plugin::ModuleBuildTiny' => '0.012',
        }),
        'installer prereq version is added',
    ) or diag 'got dist metadata: ', explain $tzil->distmeta;

    cmp_deeply(
        [
            $tzil->plugin_named('@Author::ETHER/ModuleBuildTiny'),
            $tzil->plugin_named('@Author::ETHER/StaticInstall'),
        ],
        [
            methods(default_jobs => 9, static => 'no'),
            methods(mode => 'off', dry_run => 0),
        ],
        'appropriate configurations are passed for static install',
    );

    my $build_dir = path($tzil->tempdir)->child('build');
    my $prereq_reporter = path($build_dir)->child('t', '00-report-prereqs.t')->slurp_utf8;
    like(
        $prereq_reporter,
        qr/^use Module::Metadata;$/m,
        'Module::Metadata is used as the version extractor for [Test::ReportPrereqs]',
    );
    unlike(
        $prereq_reporter,
        qr/^use ExtUtils::MakeMaker;$/m,
        'EUMM is not used as the version extractor for [Test::ReportPrereqs]',
    );

    diag 'got log messages: ', explain $tzil->log_messages
        if not Test::Builder->new->is_passing;
} };

done_testing;

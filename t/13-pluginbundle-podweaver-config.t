use strict;
use warnings;

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::Deep;
use Test::DZil;
use Test::Fatal;
use Path::Tiny;
use File::pushd 'pushd';

use lib 't/lib';
use Helper;
use NoNetworkHits;
use NoPrereqChecks;

# load this in advance, as we change directories between configuration and building
use Pod::Weaver::PluginBundle::Author::ETHER;

my $wd = pushd('t/corpus/with_no_weaver_ini');

ok(!-e 'weaver.ini', 'a weaver.ini does not exist in this directory');

my $tzil = Builder->from_config(
    { dist_root => 'does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                'GatherDir',
                [ '@Author::ETHER' => {
                    -remove => \@REMOVED_PLUGINS,
                    'RewriteVersion::Transitional.skip_version_provider' => 1,
                } ],
            ),
            path(qw(source lib Foo.pm)) => <<FOO,
package Foo;
# ABSTRACT: Hello, this is foo

1;
=pod

=cut
FOO
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

my $plugin = $tzil->plugin_named('@Author::ETHER/PodWeaver');
cmp_deeply(
    $plugin,
    noclass(superhashof({
        replacer => 'replace_with_comment',
        post_code_replacer => 'replace_with_nothing',
    })),
    'other [PodWeaver] configs survived',
);

cmp_deeply(
    $tzil->distmeta,
    superhashof({
        x_Dist_Zilla => superhashof({
            plugins => supersetof(
                {
                    class => 'Dist::Zilla::Plugin::PodWeaver',
                    config => superhashof({
                        'Dist::Zilla::Plugin::PodWeaver' => superhashof({
                            config_plugins => [ '@Author::ETHER' ],
                            # check that all plugins came from '@Author::ETHER'
                            plugins => array_each(
                                # TODO: we can use our bundle name in these
                                # sections too, by adjusting how we set up the configs
                                code(sub {
                                    ref $_[0] eq 'HASH' or return (0, 'not a HASH');
                                    $_[0]->{name} =~ m{^\@(CorePrep|Author::ETHER)/}
                                        or $_[0]->{class} =~ /^Pod::Weaver::Section::(Generic|Collect)$/
                                        or return (0, 'weaver plugin has bad name');
                                    return 1;
                                }),
                            ),
                            # TODO: Pod::Elemental::PerlMunger does not add these
                            # replacer => 'replace_with_comment',
                            # post_code_replacer => 'replace_with_nothing',
                        }),
                    }),
                    name => '@Author::ETHER/PodWeaver',
                    version => Dist::Zilla::Plugin::PodWeaver->VERSION,
                },
            ),
        }),
    }),
    'weaver plugin config is properly included in metadata - weaver.ini does not exist, so bundle is used',
)
or diag 'got distmeta: ', explain $tzil->distmeta;

diag 'got log messages: ', explain $tzil->log_messages
    if not Test::Builder->new->is_passing;

done_testing;
# IBM(c) 2013 EPL license http://www.eclipse.org/legal/epl-v10.html
#----------------------------------------------------------------------

# Plugin to interface with IBM SVC managed storage
#
use strict;

package xCAT_plugin::svc;

use xCAT::SvrUtils qw/sendmsg/;
use xCAT::SSHInteract;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

my $callback;
my $dorequest;
my %controllersessions;

sub handled_commands {
    return {
        mkstorage     => "storage:type",
        lsstorage     => "storage:type",
        detachstorage => "storage:type",
        rmstorage     => "storage:type",
        lspool        => "storage:type",
      }
}

sub detachstorage {
    my $request = shift;
    my @nodes   = @{ $request->{node} };
    my $controller;
    @ARGV = @{ $request->{arg} };
    unless (GetOptions(
            'controller=s' => \$controller,
        )) {
        foreach (@nodes) {
            sendmsg([ 1, "Error parsing arguments" ], $callback, $_);
        }
    }
    my $storagetab = xCAT::Table->new('storage');
    my $storents = $storagetab->getNodesAttribs(\@nodes, [qw/controller/]);
    unless ($controller) {
        $controller = assure_identical_table_values(\@nodes, $storents, 'controller');
    }
    my @volnames = @ARGV;
    my $wwns     = get_wwns(@nodes);
    use Data::Dumper;
    my %namemap = makehosts($wwns, controller => $controller, cfg => $storents);
    foreach my $node (keys %namemap) {
        my $host = $namemap{$node};
        my $session = establish_session(controller => $controller);
        foreach my $volname (@volnames) {
            my @rets = $session->cmd("rmvdiskhostmap -host $host $volname");
            my $ret  = $rets[0];
            if ($ret =~ m/^CMMVC5842E/) {
                sendmsg([ 1, "Node not attached to $volname" ], $callback, $node);
            }
        }
    }
}

sub rmstorage {
    my $request = shift;
    my @nodes   = @{ $request->{node} };
    my $controller;
    @ARGV = @{ $request->{arg} };
    unless (GetOptions(
            'controller=s' => \$controller,
        )) {
        foreach (@nodes) {
            sendmsg([ 1, "Error parsing arguments" ], $callback, $_);
        }
    }
    my @volnames   = @ARGV;
    my $storagetab = xCAT::Table->new('storage');
    my $storents   = $storagetab->getNodesAttribs(\@nodes, [qw/controller/]);
    unless ($controller) {
        $controller = assure_identical_table_values(\@nodes, $storents, 'controller');
    }
    detachstorage($request);
    my $session = establish_session(controller => $controller);
    foreach my $volname (@volnames) {
        my @info = $session->cmd("rmvdisk $volname");
        my $ret  = $info[0];
        if ($ret =~ m/^CMMVC5753E/) {
            foreach my $node (@nodes) {
                sendmsg([ 1, "Disk $volname does not exist" ], $callback, @nodes);
            }
        } elsif ($ret =~ m/^CMMVC5840E/) {
            foreach my $node (@nodes) {
                sendmsg([ 1, "Disk $volname is mapped to other nodes and/or busy" ], $callback, @nodes);
            }
        }
    }
}


sub lsstorage {
    my $request    = shift;
    my @nodes      = @{ $request->{node} };
    my $storagetab = xCAT::Table->new("storage", -create => 0);
    unless ($storagetab) { return; }
    my $storents = $storagetab->getNodesAttribs(\@nodes, [qw/controller/]);
    my $wwns = get_wwns(@nodes);
    foreach my $node (@nodes) {
        if ($storents and $storents->{$node} and $storents->{$node}->[0]->{controller}) {
            my $ctls = $storents->{$node}->[0]->{controller};
            foreach my $ctl (split /,/, $ctls) { # TODO: scan all controllers at once
                my $session = establish_session(controller => $ctl);
                my %namemap = makehosts($wwns, controller => $ctl, cfg => $storents);
                my @vdisks = hashifyoutput($session->cmd("lsvdisk -delim :"));
                foreach my $vdisk (@vdisks) {
                    my @maps = hashifyoutput($session->cmd("lsvdiskhostmap -delim : " . $vdisk->{'id'}));
                    foreach my $map (@maps) {
                        if ($map->{host_name} eq $namemap{$node}) {
                            sendmsg($vdisk->{name} . ': size: ' . $vdisk->{capacity} . ' id: ' . $vdisk->{vdisk_UID}, $callback, $node);
                            last;
                        }
                    }
                }
            }
        }
    }
}

sub mkstorage {
    my $request = shift;
    my @nodes   = @{ $request->{node} };
    my $shared  = 0;
    my $controller;
    my $pool;
    my $size;
    my $boot   = 0;
    my $format = 0;
    unless (ref $request->{arg}) {
        die "TODO: usage";
    }
    my $name;
    @ARGV = @{ $request->{arg} };
    unless (GetOptions(
            'format'       => \$format,
            'shared'       => \$shared,
            'controller=s' => \$controller,
            'boot'         => \$boot,
            'size=f'       => \$size,
            'name=s'       => \$name,
            'pool=s'       => \$pool,
        )) {
        foreach (@nodes) {
            sendmsg([ 1, "Error parsing arguments" ], $callback, $_);
        }
    }
    if ($shared and $boot) {
        foreach (@nodes) {
            sendmsg([ 1, "Storage can not be both shared and boot" ], $callback, $_);
        }
    }
    my $storagetab = xCAT::Table->new('storage');
    my $storents   = $storagetab->getNodesAttribs(\@nodes,
        [qw/controller storagepool size/]);
    if ($shared) {
        unless ($size) {
            foreach (@nodes) {
                sendmsg([ 1,
"Size for shared volumes must be specified as an argument"
                ], $callback, $_);
            }
        }
        unless ($pool) {
            $pool = assure_identical_table_values(\@nodes, $storents, 'storagepool');
        }
        unless ($controller) {
            $controller = assure_identical_table_values(\@nodes, $storents, 'controller');
        }
        unless (defined $pool and defined $controller) {
            return;
        }
        my %lunargs = (controller => $controller, size => $size, pool => $pool);
        if ($name) { $lunargs{name} = $name; }
        my $lun = create_lun(%lunargs);
        sendmsg($lun->{name} . ": id: " . $lun->{wwn}, $callback);
        my $wwns = get_wwns(@nodes);
        my %namemap = makehosts($wwns, controller => $controller, cfg => $storents);
        my @names = values %namemap;
        bindhosts(\@names, $lun, controller => $controller);

        if ($format) {
            my %request = (
                node    => [ $nodes[0] ],
                command => ['formatdisk'],
                arg     => [ '--id', $lun->{wwn}, '--name', $lun->{name} ]
            );
            $dorequest->(\%request, $callback);
            %request = (
                node    => \@nodes,
                command => ['rescansan'],
            );
            $dorequest->(\%request, $callback);
        }
    } else {
        foreach my $node (@nodes) {
            mkstorage_single(node => $node, size => $size, pool => $pool,
                boot => $boot, name => $name, controller => $controller,
                cfg => $storents->{$node});
        }
    }
}

sub hashifyoutput {
    my @svcoutput = @_;
    my $hdr       = shift @svcoutput;
    my @columns   = split /:/, $hdr;
    my @ret;
    foreach my $line (@svcoutput) {
        my $index  = 0;
        my %record = ();
        my $keyname;
        foreach my $datum (split /:/, $line) {
            $keyname = $columns[$index];
            $record{$keyname} = $datum;
            $index += 1;
        }
        push @ret, \%record;
    }
    pop @ret;    # discard data from prompt
    return @ret;
}

sub bindhosts {
    my $nodes   = shift;
    my $lun     = shift;
    my %args    = @_;
    my $session = establish_session(%args);
    foreach my $node (@$nodes) {

        #TODO: get what failure looks like... somehow...
        #I guess I could make something with mismatched name and see how it
        #goes
        $session->cmd("mkvdiskhostmap -force -host $node " . $lun->{id});
    }
}

sub fixup_host {
    my $session = shift;
    my $wwnlist = shift;
    my @hosts   = hashifyoutput($session->cmd("lshost -delim :"));
    my %wwnmap;
    my %hostmap;
    foreach my $host (@hosts) {
        my @hostd = $session->cmd("lshost -delim : " . $host->{name});
        foreach my $hdatum (@hostd) {
            if ($hdatum =~ m/^WWPN:(.*)$/) {
                $wwnmap{$1} = $host->{name};
                $hostmap{ $host->{name} }->{$1} = 1;
            }
        }
    }
    my $name;
    foreach my $wwn (@$wwnlist) {
        $wwn =~ s/://g;
        $wwn = uc($wwn);
        if (defined $wwnmap{$wwn}) {    # found the matching host
                #we want to give the host all the ports that may be relevant
            $name = $wwnmap{$wwn};
            foreach my $mwwn (@$wwnlist) {
                $mwwn =~ s/://g;
                $mwwn = uc($mwwn);
                if (not defined $hostmap{$name}->{$mwwn}) {
                    $session->cmd("addhostport -hbawwpn $mwwn -force $name");
                }
            }
            return $name;
        }
    }
    die "unable to find host to fixup";
}

sub makehosts {
    my $wwnmap  = shift;
    my %args    = @_;
    my $session = establish_session(%args);
    my $stortab = xCAT::Table->new('storage');
    my %nodenamemap;
    foreach my $node (keys %$wwnmap) {
        my $wwnstr = "";
        foreach my $wwn (@{ $wwnmap->{$node} }) {
            $wwn =~ s/://g;
            $wwnstr .= $wwn . ":";
        }
        chop($wwnstr);

        #TODO: what if the given wwn exists, but *not* as the nodename we want
        #the correct action is to look at hosts, see if one exists, and reuse,
        #create, or warn depending
        my @hostres = $session->cmd("mkhost -name $node -hbawwpn $wwnstr -force");
        my $result = $hostres[0];
        if ($result =~ m/^CMM/) {    # we have some exceptional case....
            if ($result =~ m/^CMMVC6035E/) {    #duplicate name and/or wwn..
                    #need to finde the host and massage it to being viable
                $nodenamemap{$node} = fixup_host($session, $wwnmap->{$node});
            } else {
                die $result . " while trying to create host";
            }
        } else {
            $nodenamemap{$node} = $node;
        }
        my @currentcontrollers = split /,/, $args{cfg}->{$node}->[0]->{controller};
        if ($args{cfg}->{$node}->[0] and $args{cfg}->{$node}->[0]->{controller}) {
            @currentcontrollers = split /,/, $args{cfg}->{$node}->[0]->{controller};
        } else {
            @currentcontrollers = ();
        }
        if (grep { $_ eq $args{controller} } @currentcontrollers) {
            next;
        }
        unshift @currentcontrollers, $args{controller};
        my $ctrstring = join ",", @currentcontrollers;
        $stortab->setNodeAttribs($node, { controller => $ctrstring });
    }
    return %nodenamemap;
}

my %wwnmap;

sub got_wwns {
    my $rsp = shift;
    foreach my $ndata (@{ $rsp->{node} }) {
        my $nodename = $ndata->{name}->[0];
        my @wwns     = ();
        foreach my $data (@{ $ndata->{data} }) {
            push @{ $wwnmap{$nodename} }, $data->{contents}->[0];
        }
    }
}

sub get_wwns {
    %wwnmap = ();
    my @nodes = @_;
    foreach my $node (@nodes) {
        $wwnmap{$node} = [];
    }
    my %request = (
        node    => \@nodes,
        command => ['rinv'],
        arg     => ['wwn']
    );
    $dorequest->(\%request, \&got_wwns);
    return \%wwnmap;
}

my $globaluser;
my $globalpass;

sub get_svc_creds {
    my $controller = shift;
    if ($globaluser and $globalpass) {
        return { 'user' => $globaluser, 'pass' => $globalpass }
    }
    my $passtab = xCAT::Table->new('passwd', -create => 0);
    my $passent = $passtab->getAttribs({ key => 'svc' }, qw/username password/);
    $globaluser = $passent->{username};
    $globalpass = $passent->{password};
    return { 'user' => $globaluser, 'pass' => $globalpass }
}

sub establish_session {
    my %args       = @_;
    my $controller = $args{controller};
    if ($controllersessions{$controller}) {
        return $controllersessions{$controller};
    }

    #need to establish a new session
    my $cred = get_svc_creds($controller);
    my $sess = new xCAT::SSHInteract(-username => $cred->{user},
        -password                => $cred->{pass},
        -host                    => $controller,
        -output_record_separator => "\r",

        #Errmode=>"return",
        #Input_Log=>"/tmp/svcdbgl",
        Prompt => '/>$/');
    unless ($sess and $sess->atprompt) { die "TODO: cleanly handle bad login" }
    $controllersessions{$controller} = $sess;
    return $sess;
}

sub create_lun {
    my %args    = @_;
    my $session = establish_session(%args);
    my $pool    = $args{pool};
    my $size    = $args{size};
    my $cmd     = "mkvdisk -iogrp io_grp0 -mdiskgrp $pool -size $size -unit gb";
    if ($args{name}) {
        $cmd .= " -name " . $args{name};
    }
    my @result = $session->cmd($cmd);
    if ($result[0] =~ m/Virtual Disk, id \[(\d*)\], successfully created/) {
        my $diskid = $1;
        my $name;
        my $wwn;
        @result = $session->cmd("lsvdisk $diskid");
        foreach (@result) {
            chomp;
            if (/^name (.*)\z/) {
                $name = $1;
            } elsif (/^vdisk_UID (.*)\z/) {
                $wwn = $1;
            }
        }
        return { name => $name, id => $diskid, wwn => $wwn };
    }
}

sub assure_identical_table_values {
    my $nodes     = shift;
    my $storents  = shift;
    my $attribute = shift;
    my $lastval;
    foreach my $node (@$nodes) {
        my $sent = $storents->{$node}->[0];
        unless ($sent) {
            sendmsg([ 1, "No $attribute in arguments or table" ],
                $callback, $node);
            return undef;
        }
        my $currval = $sent->{$attribute};
        unless ($currval) {
            sendmsg([ 1, "No $attribute in arguments or table" ],
                $callback, $node);
            return undef;
        }
        if ($lastval and $currval ne $lastval) {
            sendmsg([ 1,
"$attribute mismatch in table config, try specifying as argument" ],
                $callback, $node);
            return undef;
        }
        if (not defined $lastval) { $lastval = $currval; }
    }
    return $lastval;
}

sub mkstorage_single {
    my %args = @_;
    my $size;
    my $cfg  = $args{cfg};
    my $node = $args{node};
    my $pool;
    my $controller;
    if (defined $args{size}) {
        $size = $args{size};
    } elsif ($cfg->{size}) {
        $size = $cfg->{size};
    } else {
        sendmsg([ 1, "Size not provided via argument or storage.size" ],
            $callback, $node);
    }
    if (defined $args{pool}) {
        $pool = $args{pool};
    } elsif ($cfg->{storagepool}) {
        $pool = $cfg->{storagepool};
    } else {
        sendmsg([ 1, "Pool not provided via argument or storage.storagepool" ],
            $callback, $node);
    }
    if (defined $args{controller}) {
        $controller = $args{controller};
    } elsif ($cfg->[0]->{controller}) {
        $controller = $cfg->[0]->{controller};
        $controller =~ s/.*,//;
    }
    my %lunargs = (controller => $controller, size => $size, pool => $pool);
    if ($args{name}) {
        $lunargs{name} = $args{name} . "-" . $node;
    }
    my $lun = create_lun(%lunargs);
    sendmsg($lun->{name} . ": id: " . $lun->{wwn}, $callback, $node);
    my $wwns = get_wwns($node);
    my %namemap = makehosts($wwns, controller => $controller, cfg => { $node => $cfg });
    my @names = values %namemap;
    bindhosts(\@names, $lun, controller => $controller);
}

sub process_request {
    my $request = shift;
    $callback  = shift;
    $dorequest = shift;
    if ($request->{command}->[0] eq 'mkstorage') {
        mkstorage($request);
    } elsif ($request->{command}->[0] eq 'lsstorage') {
        lsstorage($request);
    } elsif ($request->{command}->[0] eq 'rmstorage') {
        rmstorage($request);
    } elsif ($request->{command}->[0] eq 'detachstorage') {
        detachstorage($request);
    } elsif ($request->{command}->[0] eq 'lspool') {
        lsmdiskgrp($request);
    }
    foreach (values %controllersessions) {
        $_->close();
    }
}

sub lsmdiskgrp {
    my $req = shift;
    foreach my $node (@{ $req->{node} }) {
        my $session = establish_session(controller => $node);
        my @pools = hashifyoutput($session->cmd("lsmdiskgrp -delim :"));
        foreach my $pool (@pools) {
            sendmsg($pool->{name} . " available capacity: " . $pool->{free_capacity}, $callback, $node);
            sendmsg($pool->{name} . " total capacity: " . $pool->{capacity}, $callback, $node);
        }
    }
}

1;

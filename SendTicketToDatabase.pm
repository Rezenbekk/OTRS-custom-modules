# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::ProcessManagement::TransitionAction::SendTicketToDatabase;

use strict;
use warnings;
use utf8;

use Kernel::System::ObjectManager;
use Kernel::System::VariableCheck qw(:all);

use parent qw(Kernel::System::ProcessManagement::TransitionAction::Base);



our @ObjectDependencies = (
    'Kernel::System::DB',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::Log',
    'Kernel::System::Ticket',
);

=head1 NAME

Kernel::System::ProcessManagement::TransitionAction::SendTicketToDatabase - A module to send ticket ID and its dynamic fields to a database. Must be configured by hand.

=head1 DESCRIPTION

All SendTicketToDatabase functions.

=head1 PUBLIC INTERFACE

=head2 new()

Don't use the constructor directly, use the ObjectManager instead:

    my $SendTicketToDatabaseObject = $Kernel::OM->Get('Kernel::System::ProcessManagement::TransitionAction::SendTicketToDatabase');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 Run()

    Run Data

    my $SendTicketToDatabase = $SendTicketToDatabaseActionObject->Run(
        UserID                   => 123,
        Ticket                   => \%Ticket,   # required
        ProcessEntityID          => 'P123',
        ActivityEntityID         => 'A123',
        TransitionEntityID       => 'T123',
        TransitionActionEntityID => 'TA123',
        Config                   => {
            DatabaseDSN  => 'DBI:mysql:database=123;host=localhost;', #all required
            DatabaseUser => 'login',
            DatabasePw   => 'password',
        }
    );
    Ticket contains the result of TicketGet including DynamicFields
    Config is the Config Hash stored in a Process::TransitionAction's  Config key
    Returns:

    $SendTicketToDatabaseResult = 1; # 0

    );

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    # define a common message to output in case of any error
    my $CommonMessage = "SANDBOX - ";

    # check for missing or wrong params
    my $Success = $Self->_CheckParams(
        %Param,
        CommonMessage => $CommonMessage,
    );
    return if !$Success;

    # override UserID if specified as a parameter in the TA config
    $Param{UserID} = $Self->_OverrideUserID(%Param);

    # use ticket attributes if needed
    $Self->_ReplaceTicketAttributes(%Param);

    # get dynamic field objects
    my $DynamicFieldObject        = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

    my @DynamicFieldNames = (
        "Title",
        "Author",
        "ISBN",
        "Status",
        "Supplier",
        "Price",
        "DateOfReceipt",
        "DeliveryDate"
    );

    my %df_to_sql = (
        "Title" => "title",
        "Author" => "author",
        "ISBN" => "isbn",
        "Status" => "status",
        "Supplier" => "supplier",
        "Price" => "price",
        "DateOfReceipt" => "date_of_receipt",
        "DeliveryDate" => "delivery_date"
    );

    foreach my $CurrentDynamicField (@DynamicFieldNames)
    {
        my $DynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
            Name => $CurrentDynamicField,
        );

        my $DynamicFieldValue = $DynamicFieldBackendObject->ValueGet(
            DynamicFieldConfig => $DynamicFieldConfig,
            ObjectID => $Param{Ticket}->{TicketID},
        );

        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => $CommonMessage . $DynamicFieldValue,
        );

        $df_to_sql{$CurrentDynamicField} = $DynamicFieldValue;
    }

    local $Kernel::OM = Kernel::System::ObjectManager->new(
        'Kernel::System::DB' => {
            # if you don't supply the following parameters, the ones found in
            # Kernel/Config.pm are used instead:
        
            # Keys to be specified in the parameters
            # DatabaseDSN  => 'DBI:mysql:database=123;host=localhost;',
            DatabaseDSN => $Param{Config}->{DatabaseDSN},
            #DatabaseUser => 'login',
            DatabaseUser => $Param{Config}->{DatabaseUser},
            DatabasePw => $Param{Config}->{DatabasePw},
            #DatabasePw   => 'password',
            Type         => 'mysql',
            Attribute => {
                LongTruncOk => 1,
                LongReadLen => 100*1024,
            },
        },
    );

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'error',
        Message  => $CommonMessage . $Param{Config}->{DatabaseDSN},
    );

    $Success = 0;
    
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
    $DBObject->Connect();    
    $DBObject->Do(
        SQL=> "INSERT INTO dbase.sandbox_book_tickets (ticket_id, title, author, isbn, status, supplier, price, date_of_receipt, delivery_date) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE title = ?, author = ?, isbn = ?, status = ?, supplier = ?, price = ?, date_of_receipt = ?, delivery_date = ?",
        #SQL=> "INSERT INTO dbase.sandbox_book_tickets (ticket_id, title, author, isbn, status, supplier, price) VALUES(1, 'HP', 'JKR', 'IS123', 'Approved', 'Me', '123') ON DUPLICATE KEY UPDATE author = 'JKRBBY'",
        Bind=> [\$Param{Ticket}->{TicketID},
                \$df_to_sql{'Title'},
                \$df_to_sql{'Author'},
                \$df_to_sql{'ISBN'},
                \$df_to_sql{'Status'},
                \$df_to_sql{'Supplier'},
                \$df_to_sql{'Price'},
                \$df_to_sql{'DateOfReceipt'},
                \$df_to_sql{'DeliveryDate'},
                \$df_to_sql{'Title'},
                \$df_to_sql{'Author'},
                \$df_to_sql{'ISBN'},
                \$df_to_sql{'Status'},
                \$df_to_sql{'Supplier'},
                \$df_to_sql{'Price'},
                \$df_to_sql{'DateOfReceipt'},
                \$df_to_sql{'DeliveryDate'},
                ],
    );
    my $DBError = $DBObject->Error();

    if (defined $DBError && $DBError ne ''){
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Whoops: " . $DBError,
        );
    }

    return 1;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

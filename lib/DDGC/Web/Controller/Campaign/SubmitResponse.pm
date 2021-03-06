package DDGC::Web::Controller::Campaign::SubmitResponse;
# ABSTRACT: Retrieve / mail responses for Share Campaign

use Moose;
BEGIN { extends 'Catalyst::Controller'; }

use DDGC::Config;
use Try::Tiny;
use DateTime;
use DateTime::Duration;

sub base :Chained('/') :PathPart('campaign') :CaptureArgs(0) {
	my ( $self, $c ) = @_;
	if (!$c->user) {
		$c->response->status(403);
		$c->stash->{x} = { ok => 0, errstr => "Not logged in!"};
		$c->forward( $c->view('JSON') );
		return $c->detach;
	}
	elsif (!$c->req->param('campaign_name')) {
		$c->response->status(500);
		$c->stash->{x} = {
			ok => 0, no_campaign => 1,
			errstr => "No campaign info supplied!"
		};
		$c->forward( $c->view('JSON') );
		return $c->detach;
	}
	elsif ($c->user->responded_campaign($c->req->param('campaign_name'))) {
		$c->response->status(403);
		$c->stash->{x} = {
			ok => 0, already_responded => 1,
			errstr => "You already responded to these questions. Thank you!"
		};
		$c->forward( $c->view('JSON') );
		return $c->detach;
	}
	elsif ($c->user->get_first_available_campaign ne $c->req->param('campaign_name')) {
		$c->response->status(403);
		$c->stash->{x} = {
			ok => 0, no_access_yet => 1,
			errstr => "This is not yet open",
		};
		$c->forward( $c->view('JSON') );
		return $c->detach;
	}
}

sub respond : Chained('base') : PathPart('respond') : Args(0) {
	my ( $self, $c ) = @_;
	#$c->require_action_token;

	my $to = $c->d->config->share_email // 'sharewear@duckduckgo.com';
	my $from = 'noreply@dukgo.com';
	my $username = $c->user->username;
	my $campaign_name = $c->req->param('campaign_name');;
	my $subject = "$campaign_name response from $username";
	my $campaign = $c->d->config->campaigns->{ $campaign_name };

	for (1..3) {
		if (!$c->req->param( 'question' . $_ )) {
			$c->response->status(500);
			$c->stash->{x} = {
				ok => 0, fields_empty => 1,
				errstr => "Please fill all fields before submitting. Thanks."
			};
			$c->forward( $c->view('JSON') );
			return $c->detach;
		}

		$c->stash->{ 'question' . $_ } = $campaign->{ 'question' . $_ };
		$c->stash->{ 'answer' . $_ } = $c->req->param( 'question' . $_ );
	}

	if ($campaign_name eq 'share') {
		my $report_url = $c->chained_uri( 'Admin::Campaign', 'bad_user_response', { user => $username, campaign => $campaign_name} );
		$c->stash->{'extra'} = <<"BAD_RESPONSE_LINK"
		<a href="$report_url">
			Report bad responses
		</a>.
BAD_RESPONSE_LINK
	}

	my $error = 0;
	try {
		$c->d->postman->template_mail(
			$to, $from, $subject, 'campaign', $c->stash
		);
	}
	catch {
		$error = 1;
	};

	if ($error) {
		$c->response->status(500);
		$c->stash->{x} = {
			ok => 0, mailer_error => 1,
			errstr => "Sorry, there was a problem submitting your response. Please try again later."
		};
		$c->forward( $c->view('JSON') );
		return $c->detach;
	}

	$c->user->set_responded_campaign($campaign_name);

	my $return_on;
	my $coupon;

	if ($campaign_name eq 'share') {
		$return_on = (DateTime->now + DateTime::Duration->new( days => 30 ))->strftime("%B %e");
	}
	if ($campaign_name eq 'share_followup') {
		$coupon = $c->user->get_coupon($campaign_name, { create => 1 }) || "NO COUPON :(";
	}
	$c->stash->{x} = {
		ok => 1, return_on => $return_on, coupon => $coupon,
		campaign_id => $c->req->param('campaign_id'),
	};
	$c->forward( $c->view('JSON') );
	return $c->detach;
}

__PACKAGE__->meta->make_immutable;

1;


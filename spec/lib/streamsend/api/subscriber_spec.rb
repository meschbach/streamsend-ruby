require File.join(File.dirname(__FILE__), "../../../spec_helper")
require "ostruct"

module StreamSend
  module Api
    describe "Subscriber" do
      before do
        WebMock.enable!
        stub_http_request(:any, //).to_return(:body => "Page not found.", :status => 404)

        @username = "scott"
        @password = "topsecret"
        @host = "test.host"

        xml = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <audiences type="array">
          <audience>
            <id type="integer">2</id>
          </audience>
        </audiences>
        XML
        stub_http_request(:get, "http://#{@username}:#{@password}@#{@host}/audiences.xml").to_return(:body => xml)

        StreamSend::Api.configure(@username, @password, @host)
      end

      after do
        WebMock.disable!
      end

      describe ".audience_id" do
        it "should return the id of the first audience" do
          StreamSend::Api::Subscriber.audience_id.should == 2
        end

        it "should throw an error on failure" do
          xml = <<-XML
        <?xml version="1.0" encoding="UTF-8"?>
        <foo></foo>
          XML
          stub_http_request(:get, "http://#{@username}:#{@password}@#{@host}/audiences.xml").to_return(:body => xml)
          expect { StreamSend::Api::Subscriber.audience_id.should == 2 }.to raise_error(StreamSend::Api::Exception)
        end
      end

      describe ".clear_audience" do
        it "allows the audience_id to be retrieved again" do
          @resource = StreamSend::Api::Resource.new({"name" => "jeff"})
          StreamSend::Api.should_receive(:get).with("/audiences.xml").and_return(OpenStruct.new(:parsed_response => { "audiences" => [{"id" => 2}] }))
          StreamSend::Api::Resource.audience_id.should == 2
          StreamSend::Api.should_receive(:get).with("/audiences.xml").and_return(OpenStruct.new(:parsed_response => { "audiences" => [{"id" => 1}] }))
          StreamSend::Api::Resource.audience_id.should == 2
          StreamSend::Api::Resource.clear_audience
          StreamSend::Api::Resource.audience_id.should == 1
        end
      end

      describe ".index" do
        describe "with subscribers" do
          before(:each) do
            xml = <<-XML
            <?xml version="1.0" encoding="UTF-8"?>
            <people type="array">
              <person>
                <id type="integer">2</id>
                <email-address>scott@gmail.com</email-address>
                <created-at type="datetime">2009-09-18T01:27:05Z</created-at>
              </person>
            </people>
            XML

            stub_http_request(:get, "http://#{@username}:#{@password}@#{@host}/audiences/2/people.xml?").to_return(:body => xml)
          end

          it "should return array of one subscriber object" do
            subscribers = StreamSend::Api::Subscriber.index
            subscribers.size.should == 1

            subscribers.first.should be_instance_of(StreamSend::Api::Subscriber)
            subscribers.first.id.should == 2
            subscribers.first.email_address.should == "scott@gmail.com"
            subscribers.first.created_at.should == Time.parse("2009-09-18T01:27:05Z")
          end
        end

        describe "with no subscribers" do
          before(:each) do
            xml = <<-XML
            <?xml version="1.0" encoding="UTF-8"?>
            <people type="array"/>
            XML

            stub_http_request(:get, "http://#{@username}:#{@password}@#{@host}/audiences/2/people.xml?").to_return(:body => xml)
          end

          it "should return an empty array" do
            StreamSend::Api::Subscriber.index.should == []
          end
        end

        describe "with invalid audience" do
          before(:each) do
            xml = <<-XML
            <?xml version="1.0" encoding="UTF-8"?>
            <people type="array"/>
            XML

            stub_http_request(:get, "http://#{@username}:#{@password}@#{@host}/audiences/99/people.xml").to_return(:body => xml)
          end

          it "should raise an exception" do
            expect do
              StreamSend::Api::Subscriber.index
            end.to raise_error(ApiException)
          end
        end
      end

      describe ".find" do
        describe "with matching subscriber" do
          before(:each) do
            xml = <<-XML
            <?xml version="1.0" encoding="UTF-8"?>
            <people type="array">
              <person>
                <id type="integer">2</id>
                <email-address>scott@gmail.com</email-address>
                <created-at type="datetime">2009-09-18T01:27:05Z</created-at>
              </person>
            </people>
            XML

            stub_http_request(:get, "http://#{@username}:#{@password}@#{@host}/audiences/2/people.xml?email_address=scott@gmail.com").to_return(:body => xml)
          end

          it "should return subscriber" do
            subscriber = StreamSend::Api::Subscriber.find("scott@gmail.com")

            subscriber.should be_instance_of(StreamSend::Api::Subscriber)
            subscriber.id.should == 2
            subscriber.email_address.should == "scott@gmail.com"
            subscriber.created_at.should == Time.parse("2009-09-18T01:27:05Z")
          end
        end

        describe "with invalid audience" do
          before(:each) do
            xml = <<-XML
            <?xml version="1.0" encoding="UTF-8"?>
            <people type="array"\>
            XML

            stub_http_request(:get, "http://#{@username}:#{@password}@#{@host}/audiences/99/people.xml?email_address=bad.email@gmail.com").to_return(:body => xml)
          end

          it "should raise an exception" do
            lambda { StreamSend::Api::Subscriber.find("scott@gmail.com") }.should raise_error
          end
        end
      end

      describe ".create" do
        describe "with valid subscriber parameters" do
          describe "with no existing subscribers using the given email address" do
            before(:each) do
              stub_http_request(:post, /audiences\/2\/people.xml/).with(:person => {"email_address" => "foo@bar.com", "first_name" => "JoeBob"}).to_return(:body => "", :headers => {"location" => "http://test.host/audiences/2/people/1"}, :status => 201)
            end

            it "should return the new subscriber's id" do
              subscriber_id = StreamSend::Api::Subscriber.create({"email_address" => "foo@bar.com", "first_name" => "JoeBob"})

              subscriber_id.should_not be_nil
              subscriber_id.should == 1
            end
          end

          describe "when receiving a semantic error" do
            describe "with a single error" do
              let( :error1 ){ "Email address has already been taken" }

              before(:each) do
                response_body = <<-XML
<errors>
  <error>#{error1}</error>
</errors>
                XML
                stub_http_request(:post, /audiences\/2\/people.xml/).with(:person => {"email_address" => "foo@bar.com", "first_name" => "JoeBob"}).to_return(:status => 422, :body => response_body )
              end

              it "should raise an exception" do
                expect do
                  subscriber_id = StreamSend::Api::Subscriber.create({"email_address" => "foo@bar.com", "first_name" => "JoeBob"})
                end.to raise_error( StreamSend::Api::SemanticException )
              end

              it "should pass on the errors" do
                captured_problem = nil
                begin
                  subscriber_id = StreamSend::Api::Subscriber.create({"email_address" => "foo@bar.com", "first_name" => "JoeBob"})
                rescue StreamSend::Api::SemanticException => problem
                  captured_problem = problem
                end
                expect(captured_problem.errors.count).to be(1)
                expect(captured_problem.errors).to include(error1)
              end
            end
          end

          describe "with multiple errors" do
            let( :error1 ){ "bonjour" }
            let( :error2 ){ "some other string you are unlikely to copy and paste" }

            before(:each) do
              response_body = <<-XML
<errors>
  <error>#{error1}</error>
  <error>#{error2}</error>
</errors>
XML
              stub_http_request(:post, /audiences\/2\/people.xml/).with(:person => {"email_address" => "foo@bar.com", "first_name" => "JoeBob"}).to_return(:status => 422, :body => response_body )
            end

            it "should pass on the errors" do
              captured_problem = nil
              begin
                subscriber_id = StreamSend::Api::Subscriber.create({"email_address" => "foo@bar.com", "first_name" => "JoeBob"})
              rescue StreamSend::Api::SemanticException => problem
                captured_problem = problem
              end
              expect(captured_problem.errors.count).to eq( 2 )
              expect(captured_problem.errors).to include(error1, error2)
            end
          end
        end
      end

      describe "#show" do
        describe "with valid subscriber instance" do
          before(:each) do
            xml = <<-XML
            <?xml version="1.0" encoding="UTF-8"?>
            <person>
              <id type="integer">2</id>
              <email-address>scott@gmail.com</email-address>
              <created-at type="datetime">2009-09-18T01:27:05Z</created-at>
              <first-name>Scott</first-name>
              <last-name>Albertson</last-name>
            </person>
            XML

            stub_http_request(:get, "http://#{@username}:#{@password}@#{@host}/audiences/1/people/2.xml").to_return(:body => xml)
          end

          it "should return subscriber" do
            subscriber = StreamSend::Api::Subscriber.new({"id" => 2, "audience_id" => 1}).show

            subscriber.should be_instance_of(StreamSend::Api::Subscriber)
            subscriber.id.should == 2
            subscriber.email_address.should == "scott@gmail.com"
            subscriber.created_at.should == Time.parse("2009-09-18T01:27:05Z")
            subscriber.first_name.should == "Scott"
            subscriber.last_name.should == "Albertson"
          end
        end

        describe "with invalid subscriber instance" do
          it "should raise exception" do
            lambda { StreamSend::Api::Subscriber.new({"id" => 99, "audience_id" => 1}).show }.should raise_error
          end
        end

        describe "with invalid audience" do
          it "should raise exception" do
            lambda { StreamSend::Api::Subscriber.new({"id" => 2}).show }.should raise_error
          end
        end
      end

      describe "#activate" do
        before(:each) do
          stub_http_request(:post, "http://#{@username}:#{@password}@#{@host}/audiences/1/people/2/activate.xml").to_return(:body => nil)
        end

        describe "with valid subscriber" do
          it "should be successful" do
            response = StreamSend::Api::Subscriber.new({"id" => 2, "audience_id" => 1}).activate
            response.should be_true
          end
        end

        describe "with invalid subscriber" do
          it "should raise exception" do
            lambda { StreamSend::Api::Subscriber.new({"id" => 99, "audience_id" => 1}).activate }.should raise_error
          end
        end
      end

      describe "#unsubscribe" do
        before(:each) do
          stub_http_request(:post, "http://#{@username}:#{@password}@#{@host}/audiences/1/people/2/unsubscribe.xml").to_return(:body => nil)
        end

        describe "with valid subscriber" do
          it "should be successful" do
            response = StreamSend::Api::Subscriber.new({"id" => 2, "audience_id" => 1}).unsubscribe
            response.should be_true
          end
        end

        describe "with invalid subscriber" do
          it "should raise exception" do
            lambda { StreamSend::Api::Subscriber.new({"id" => 99, "audience_id" => 1}).unsubscribe }.should raise_error
          end
        end
      end

      describe "#destroy" do
        let( :subscriber ){
          StreamSend::Api::Subscriber.new({"id"=> 2, "audience_id" => 1})
        }
        let( :uri ){ "http://#{@username}:#{@password}@#{@host}/audiences/1/people/2.xml" }

        it "returns true when destroyed" do
          stub_http_request(:delete, uri ).to_return(:body => nil)
          expect(subscriber.destroy).to be_true
        end

        it "throws a LockedError when locked" do
          stub_http_request(:delete, uri ).to_return(:status => 423, :body => nil)
          expect do
            subscriber.destroy
          end.to raise_error( LockedError )
        end

        it "throws unexpected response with any other exception" do
          stub_http_request(:delete, uri ).to_return(:status => 500, :body => "Error text meant for HCI")
          expect do
            subscriber.destroy
          end.to raise_error( UnexpectedResponse )
        end
      end
    end
  end
end

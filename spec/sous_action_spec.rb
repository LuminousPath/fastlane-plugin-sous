describe Fastlane::Actions::SousAction do
  describe '#run' do
    it 'prints a message' do
      expect(Fastlane::UI).to receive(:message).with("The sous plugin is working!")

      Fastlane::Actions::SousAction.run(nil)
    end
  end
end

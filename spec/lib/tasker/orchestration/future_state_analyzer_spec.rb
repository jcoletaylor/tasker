# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Orchestration::FutureStateAnalyzer do
  let(:analyzer) { described_class.new(future) }

  describe '#should_cancel?' do
    context 'when future is pending' do
      let(:future) { double('future', pending?: true) }

      it 'returns true' do
        expect(analyzer.should_cancel?).to be true
      end
    end

    context 'when future is not pending' do
      let(:future) { double('future', pending?: false) }

      it 'returns false' do
        expect(analyzer.should_cancel?).to be false
      end
    end
  end

  describe '#should_wait_for_completion?' do
    context 'when future is executing' do
      let(:future) do
        double('future',
               incomplete?: true,
               unscheduled?: false,
               pending?: false)
      end

      it 'returns true' do
        expect(analyzer.should_wait_for_completion?).to be true
      end
    end

    context 'when future is not executing' do
      let(:future) do
        double('future',
               incomplete?: false,
               unscheduled?: false,
               pending?: false)
      end

      it 'returns false' do
        expect(analyzer.should_wait_for_completion?).to be false
      end
    end
  end

  describe '#can_ignore?' do
    context 'when future is completed' do
      let(:future) { double('future', complete?: true, unscheduled?: false) }

      it 'returns true' do
        expect(analyzer.can_ignore?).to be true
      end
    end

    context 'when future is unscheduled' do
      let(:future) { double('future', complete?: false, unscheduled?: true) }

      it 'returns true' do
        expect(analyzer.can_ignore?).to be true
      end
    end

    context 'when future is neither completed nor unscheduled' do
      let(:future) { double('future', complete?: false, unscheduled?: false) }

      it 'returns false' do
        expect(analyzer.can_ignore?).to be false
      end
    end
  end

  describe '#executing?' do
    context 'when future is incomplete, scheduled, and not pending' do
      let(:future) do
        double('future',
               incomplete?: true,
               unscheduled?: false,
               pending?: false)
      end

      it 'returns true' do
        expect(analyzer.executing?).to be true
      end
    end

    context 'when future is complete' do
      let(:future) do
        double('future',
               incomplete?: false,
               unscheduled?: false,
               pending?: false)
      end

      it 'returns false' do
        expect(analyzer.executing?).to be false
      end
    end

    context 'when future is unscheduled' do
      let(:future) do
        double('future',
               incomplete?: true,
               unscheduled?: true,
               pending?: false)
      end

      it 'returns false' do
        expect(analyzer.executing?).to be false
      end
    end

    context 'when future is pending' do
      let(:future) do
        double('future',
               incomplete?: true,
               unscheduled?: false,
               pending?: true)
      end

      it 'returns false' do
        expect(analyzer.executing?).to be false
      end
    end
  end

  describe '#completed?' do
    context 'when future is complete' do
      let(:future) { double('future', complete?: true) }

      it 'returns true' do
        expect(analyzer.completed?).to be true
      end
    end

    context 'when future is not complete' do
      let(:future) { double('future', complete?: false) }

      it 'returns false' do
        expect(analyzer.completed?).to be false
      end
    end
  end

  describe '#unscheduled?' do
    context 'when future is unscheduled' do
      let(:future) { double('future', unscheduled?: true) }

      it 'returns true' do
        expect(analyzer.unscheduled?).to be true
      end
    end

    context 'when future is not unscheduled' do
      let(:future) { double('future', unscheduled?: false) }

      it 'returns false' do
        expect(analyzer.unscheduled?).to be false
      end
    end
  end

  describe '#pending?' do
    context 'when future is pending' do
      let(:future) { double('future', pending?: true) }

      it 'returns true' do
        expect(analyzer.pending?).to be true
      end
    end

    context 'when future is not pending' do
      let(:future) { double('future', pending?: false) }

      it 'returns false' do
        expect(analyzer.pending?).to be false
      end
    end
  end

  describe '#state_description' do
    context 'when future is unscheduled' do
      let(:future) do
        double('future', unscheduled?: true, pending?: false, incomplete?: true, fulfilled?: false, rejected?: false,
                         cancelled?: false)
      end

      it 'returns "unscheduled"' do
        expect(analyzer.state_description).to eq('unscheduled')
      end
    end

    context 'when future is pending' do
      let(:future) do
        double('future', unscheduled?: false, pending?: true, incomplete?: true, fulfilled?: false, rejected?: false,
                         cancelled?: false)
      end

      it 'returns "pending"' do
        expect(analyzer.state_description).to eq('pending')
      end
    end

    context 'when future is executing' do
      let(:future) do
        double('future', unscheduled?: false, pending?: false, incomplete?: true, fulfilled?: false, rejected?: false,
                         cancelled?: false)
      end

      it 'returns "executing"' do
        expect(analyzer.state_description).to eq('executing')
      end
    end

    context 'when future is fulfilled' do
      let(:future) do
        double('future', unscheduled?: false, pending?: false, incomplete?: false, fulfilled?: true, rejected?: false,
                         cancelled?: false)
      end

      it 'returns "fulfilled"' do
        expect(analyzer.state_description).to eq('fulfilled')
      end
    end

    context 'when future is rejected' do
      let(:future) do
        double('future', unscheduled?: false, pending?: false, incomplete?: false, fulfilled?: false, rejected?: true,
                         cancelled?: false)
      end

      it 'returns "rejected"' do
        expect(analyzer.state_description).to eq('rejected')
      end
    end

    context 'when future is cancelled' do
      let(:future) do
        double('future', unscheduled?: false, pending?: false, incomplete?: false, fulfilled?: false, rejected?: false,
                         cancelled?: true)
      end

      it 'returns "cancelled"' do
        expect(analyzer.state_description).to eq('cancelled')
      end
    end

    context 'when future state is unknown' do
      let(:future) do
        double('future', unscheduled?: false, pending?: false, incomplete?: false, fulfilled?: false, rejected?: false,
                         cancelled?: false)
      end

      it 'returns "unknown"' do
        expect(analyzer.state_description).to eq('unknown')
      end
    end
  end

  describe '#debug_state' do
    let(:future) do
      double('future',
             pending?: true,
             complete?: false,
             incomplete?: true,
             unscheduled?: false,
             fulfilled?: false,
             rejected?: false,
             cancelled?: false)
    end

    it 'returns comprehensive state information' do
      result = analyzer.debug_state

      expect(result).to include(
        state_description: 'pending',
        should_cancel: true,
        should_wait: false,
        can_ignore: false,
        raw_states: {
          pending: true,
          complete: false,
          incomplete: true,
          unscheduled: false,
          fulfilled: false,
          rejected: false,
          cancelled: false
        }
      )
    end
  end

  describe 'real Concurrent::Future integration' do
    context 'with an unscheduled future' do
      let(:future) { Concurrent::Future.new { 42 } }

      it 'correctly identifies unscheduled state' do
        expect(analyzer.unscheduled?).to be true
        expect(analyzer.should_cancel?).to be false
        expect(analyzer.should_wait_for_completion?).to be false
        expect(analyzer.can_ignore?).to be true
        expect(analyzer.state_description).to eq('unscheduled')
      end
    end

    context 'with a completed future' do
      let(:future) do
        f = Concurrent::Future.execute { 42 }
        f.wait # Ensure it completes
        f
      end

      it 'correctly identifies completed state' do
        expect(analyzer.completed?).to be true
        expect(analyzer.should_cancel?).to be false
        expect(analyzer.should_wait_for_completion?).to be false
        expect(analyzer.can_ignore?).to be true
        expect(analyzer.state_description).to eq('fulfilled')
      end
    end

    context 'with a rejected future' do
      let(:future) do
        f = Concurrent::Future.execute { raise StandardError, 'test error' }
        f.wait # Ensure it completes
        f
      end

      it 'correctly identifies rejected state' do
        expect(analyzer.completed?).to be true
        expect(analyzer.should_cancel?).to be false
        expect(analyzer.should_wait_for_completion?).to be false
        expect(analyzer.can_ignore?).to be true
        expect(analyzer.state_description).to eq('rejected')
      end
    end
  end
end

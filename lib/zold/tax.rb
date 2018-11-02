# frozen_string_literal: true

# Copyright (c) 2018 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require_relative 'key'
require_relative 'id'
require_relative 'wallet'
require_relative 'amount'

# Tax transaction.
#
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
module Zold
  # A single tax payment
  class Tax
    # The exact score a wallet can/must buy in order to pay taxes.
    EXACT_SCORE = 8

    # The maximum allowed amount in one transaction.
    # The correct amount should be 1 ZLD, but we allow bigger amounts
    # now since the amount of nodes in the network is still small. When
    # the network grows up, let's put this number back to 1 ZLD.
    MAX_PAYMENT = Amount.new(zld: 16.0)

    # This is how much we charge per one transaction per hour
    # of storage. A wallet of 4096 transactions will pay
    # approximately 16ZLD per year.
    # Here is the formula: 16.0 / (365 * 24) / 4096 = 1915
    # But I like the 1917 number better.
    FEE = Amount.new(zents: 1917)

    # The maximum debt we can tolerate at the wallet. If the debt
    # is bigger than this threshold, nodes must stop accepting PUSH.
    TRIAL = Amount.new(zld: 1.0)

    # Text prefix for taxes details
    PREFIX = 'TAXES'

    def initialize(wallet, ignore_score_weakness: false)
      raise "The wallet must be of type Wallet: #{wallet.class.name}" unless wallet.is_a?(Wallet)
      @wallet = wallet
      @ignore_score_weakness = ignore_score_weakness
    end

    # Check whether this tax payment already exists in the wallet.
    def exists?(details)
      !@wallet.txns.find { |t| t.details.start_with?("#{Tax::PREFIX} ") && t.details == details }.nil?
    end

    def details(best)
      "#{Tax::PREFIX} #{best.reduced(Tax::EXACT_SCORE).to_text}"
    end

    def pay(pvt, best)
      @wallet.sub([Tax::MAX_PAYMENT, debt].min, best.invoice, pvt, details(best))
    end

    def in_debt?
      debt > Tax::TRIAL
    end

    def to_text
      "A=#{@wallet.age.round} hours, F=#{Tax::FEE.to_i}z/th, T=#{@wallet.txns.count}t, Paid=#{paid}"
    end

    def debt
      Tax::FEE * @wallet.txns.count * @wallet.age - paid
    end

    def paid
      txns = @wallet.txns
      scored = txns.map do |t|
        pfx, body = t.details.split(' ', 2)
        next if pfx != Tax::PREFIX || body.nil?
        score = Score.parse_text(body)
        next if !score.valid? || score.value != Tax::EXACT_SCORE
        next if score.strength < Score::STRENGTH && !@ignore_score_weakness
        next if t.amount > Tax::MAX_PAYMENT
        t
      end.compact.uniq(&:details)
      scored.empty? ? Amount::ZERO : scored.map(&:amount).inject(&:+) * -1
    end
  end
end

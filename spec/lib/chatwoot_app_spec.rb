require 'rails_helper'

RSpec.describe ChatwootApp do
  describe '.extensions' do
    # A imagem de revenda remove enterprise/ e mantem custom/. Antes, custom? verdadeiro fazia
    # extensions devolver 'enterprise' mesmo sem a pasta, e o injetor de modulos estourava
    # NoMethodError no boot ao chamar const_defined? sobre o false que const_get_maybe_false
    # devolve. Isso derrubava a aplicacao inteira, nao so os recursos enterprise.
    it 'omits enterprise when only custom is present' do
      allow(described_class).to receive_messages(enterprise?: false, custom?: true)

      expect(described_class.extensions).to eq(['custom'])
    end

    it 'lists both when both are present' do
      allow(described_class).to receive_messages(enterprise?: true, custom?: true)

      expect(described_class.extensions).to eq(%w[enterprise custom])
    end

    it 'lists enterprise alone when custom is absent' do
      allow(described_class).to receive_messages(enterprise?: true, custom?: false)

      expect(described_class.extensions).to eq(['enterprise'])
    end

    it 'lists nothing when neither is present' do
      allow(described_class).to receive_messages(enterprise?: false, custom?: false)

      expect(described_class.extensions).to be_empty
    end
  end

  # O injetor percorre extensions e busca o namespace de cada uma. Um nome sem namespace
  # correspondente e o caminho que quebrava; o teste guarda o contrato entre os dois.
  describe 'module injection over the listed extensions' do
    it 'does not raise for an extension whose namespace does not exist' do
      allow(described_class).to receive(:extensions).and_return(['nonexistent'])

      expect { Class.new.include_mod_with('Concerns::Account') }.not_to raise_error
    end
  end
end

// Modelos de tela (view models) do Otimizador Vinicius v2.0
// Compilado em tempo de execução pelo PowerShell (Add-Type, C# 5).
// Reaproveitável na v3.0 em C#/.NET.
using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Otz
{
    public class Notificavel : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;

        protected void Avisar(string nome)
        {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h != null) h(this, new PropertyChangedEventArgs(nome));
        }

        protected bool Definir<T>(ref T campo, T valor, [CallerMemberName] string nome = null)
        {
            if (object.Equals(campo, valor)) return false;
            campo = valor;
            Avisar(nome);
            return true;
        }
    }

    // Um ajuste do catálogo, como aparece na lista
    public class Ajuste : Notificavel
    {
        public string Id { get; set; }
        public string Nome { get; set; }
        public string Resumo { get; set; }
        public string Detalhe { get; set; }
        public string Indicado { get; set; }
        public string Atencao { get; set; }
        public string Categoria { get; set; }
        public string Tecnico { get; set; }
        public string ComoDesfazer { get; set; }
        public string Confirmar { get; set; }
        public string Tipo { get; set; }          // ajuste | acao
        public string Risco { get; set; }         // seguro | moderado | avancado
        public string Reinicio { get; set; }      // nenhum | explorer | logoff | reiniciar
        public string[] Perfis { get; set; }
        public int Ordem { get; set; }

        public bool TemAtencao { get { return !string.IsNullOrEmpty(Atencao); } }
        public bool TemIndicado { get { return !string.IsNullOrEmpty(Indicado); } }
        public bool TemReinicio { get { return Reinicio != null && Reinicio != "nenhum"; } }

        public string RiscoTexto
        {
            get
            {
                switch (Risco) { case "moderado": return "Moderado"; case "avancado": return "Avançado"; default: return "Seguro"; }
            }
        }

        public string RiscoDica
        {
            get
            {
                switch (Risco)
                {
                    case "moderado": return "Moderado: tem um efeito colateral que vale conhecer. Leia a seção Atenção.";
                    case "avancado": return "Avançado: troca segurança ou estabilidade por desempenho. Nunca entra nos perfis.";
                    default: return "Seguro: não traz risco ao sistema e pode ser desfeito.";
                }
            }
        }

        public string ReinicioTexto
        {
            get
            {
                switch (Reinicio)
                {
                    case "explorer": return "Recarrega a barra de tarefas";
                    case "logoff": return "Vale após sair e entrar na conta";
                    case "reiniciar": return "Vale após reiniciar o PC";
                    default: return "Vale na hora";
                }
            }
        }

        bool _selecionado;
        public bool Selecionado { get { return _selecionado; } set { Definir(ref _selecionado, value); } }

        bool _habilitado = true;
        public bool Habilitado { get { return _habilitado; } set { if (Definir(ref _habilitado, value)) Avisar("TemMotivo"); } }

        string _motivo = "";
        public string Motivo { get { return _motivo; } set { if (Definir(ref _motivo, value)) Avisar("TemMotivo"); } }
        public bool TemMotivo { get { return !_habilitado && !string.IsNullOrEmpty(_motivo); } }

        // verificando | aplicado | parcial | nao | acao | na | erro
        string _estado = "verificando";
        public string Estado
        {
            get { return _estado; }
            set { if (Definir(ref _estado, value)) { Avisar("EstadoTexto"); } }
        }

        string _estadoDetalhe = "";
        public string EstadoDetalhe
        {
            get { return _estadoDetalhe; }
            set { if (Definir(ref _estadoDetalhe, value)) { Avisar("EstadoTexto"); Avisar("TemEstadoDetalhe"); } }
        }
        public bool TemEstadoDetalhe { get { return !string.IsNullOrEmpty(_estadoDetalhe); } }

        public string EstadoTexto
        {
            get
            {
                switch (_estado)
                {
                    case "aplicado": return "Aplicado";
                    case "parcial": return "Parcial";
                    case "nao": return "Pendente";
                    case "acao": return "Ação";
                    case "na": return "Não se aplica";
                    case "erro": return "Erro ao ler";
                    default: return "Verificando";
                }
            }
        }

        bool _podeDesfazer;
        public bool PodeDesfazer { get { return _podeDesfazer; } set { Definir(ref _podeDesfazer, value); } }

        // Execução: "" | fila | executando | ok | erro | aviso | ignorado | simulado
        string _execucao = "";
        public string Execucao { get { return _execucao; } set { Definir(ref _execucao, value); } }

        string _execucaoTexto = "";
        public string ExecucaoTexto
        {
            get { return _execucaoTexto; }
            set { if (Definir(ref _execucaoTexto, value)) Avisar("TemExecucaoTexto"); }
        }
        public bool TemExecucaoTexto { get { return !string.IsNullOrEmpty(_execucaoTexto); } }
    }

    // Programa que abre com o Windows
    public class ItemInicio : Notificavel
    {
        public string Nome { get; set; }
        public string Comando { get; set; }
        public string Escopo { get; set; }
        public string Aprovado { get; set; }

        bool _ativo;
        public bool Ativo { get { return _ativo; } set { Definir(ref _ativo, value); } }
    }

    // Linha genérica de lista (alertas, portas, histórico, DNS...)
    public class Linha : Notificavel
    {
        public string Titulo { get; set; }
        public string Texto { get; set; }
        public string Extra { get; set; }
        public string Tag { get; set; }
        public string Nivel { get; set; }     // ok | alto | medio | info | erro
        public string Icone { get; set; }
        public double Valor { get; set; }     // barras (DNS)
        public bool TemTexto { get { return !string.IsNullOrEmpty(Texto); } }
        public bool TemExtra { get { return !string.IsNullOrEmpty(Extra); } }

        bool _marcado;
        public bool Marcado { get { return _marcado; } set { Definir(ref _marcado, value); } }

        object _filhos;
        public object Filhos { get { return _filhos; } set { Definir(ref _filhos, value); } }
    }
}
